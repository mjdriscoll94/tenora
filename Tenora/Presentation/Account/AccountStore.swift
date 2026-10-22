import Foundation

@MainActor
final class AccountStore: ObservableObject {
    enum State: Equatable {
        case localOnly
        case restoring
        case signedOut
        case needsAssociation(AuthenticatedAdult, interrupted: Bool)
        case profileSwitchRequired(AuthenticatedAdult, LocalProfileAssociation, activated: Bool)
        case authenticated(AuthenticatedAdult, LocalProfileAssociation)
        case sessionExpired
        case sessionRevoked
    }

    @Published private(set) var state: State = .localOnly
    @Published private(set) var isWorking = false
    @Published var message: String?

    let isConfigured: Bool
    private let provider: AdultAuthenticationProvider
    private let associations: ProfileAssociationRepository
    private let profiles: ProfileRepository
    private let widgetGroup: UserDefaults?
    private var hasRestored = false

    init(
        provider: AdultAuthenticationProvider,
        associations: ProfileAssociationRepository,
        profiles: ProfileRepository,
        widgetGroup: UserDefaults?
    ) {
        self.provider = provider
        self.associations = associations
        self.profiles = profiles
        self.widgetGroup = widgetGroup
        isConfigured = provider.isConfigured
        state = provider.isConfigured ? .signedOut : .localOnly
    }

    convenience init(provider: AdultAuthenticationProvider) {
        self.init(
            provider: provider,
            associations: UserDefaultsProfileAssociationRepository(),
            profiles: UserDefaultsProfileRepository(),
            widgetGroup: UserDefaults(suiteName: WidgetSnapshot.groupID)
        )
    }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        guard isConfigured else { state = .localOnly; return }
        state = .restoring
        do {
            guard let session = try await provider.restoreSession() else {
                state = .signedOut
                return
            }
            try await accept(session)
        } catch {
            handle(error)
        }
    }

    func signInWithApple(identityToken: String, rawNonce: String) async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let session = try await provider.signInWithApple(
                AppleIdentityCredential(identityToken: identityToken, rawNonce: rawNonce)
            )
            try await accept(session)
        } catch {
            handle(error)
        }
    }

    func associateCurrentProfile() {
        guard case .needsAssociation(let adult, _) = state else { return }
        associate(adult: adult, profileID: profiles.activeProfileID)
    }

    func associateSeparateProfile() {
        guard case .needsAssociation(let adult, _) = state else { return }
        associate(adult: adult, profileID: LocalProfileID(rawValue: "account.\(adult.userID.uuidString.lowercased())"))
    }

    func discardInterruptedAssociation() {
        guard case .needsAssociation(let adult, true) = state else { return }
        associations.removePending(accountUserID: adult.userID)
        state = .needsAssociation(adult, interrupted: false)
        message = "The unfinished connection was removed. No local data was changed."
    }

    func finishInterruptedAssociation() {
        guard case .needsAssociation(let adult, true) = state else { return }
        do {
            let association = try associations.complete(accountUserID: adult.userID)
            applyCompleted(association, to: adult)
            message = "Profile connected. Your data is still stored only on this device."
        } catch {
            message = error.localizedDescription
        }
    }

    func activateAssociatedProfile() {
        guard case .profileSwitchRequired(let adult, let association, false) = state else { return }
        blankWidgetsBeforeProfileSwitch(to: association.profileID)
        profiles.activate(association.profileID)
        state = .profileSwitchRequired(adult, association, activated: true)
    }

    func signOut() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await provider.signOut()
            state = isConfigured ? .signedOut : .localOnly
            message = "Signed out on this device. Your local data was not removed."
        } catch {
            handle(error)
        }
    }

    func report(_ error: Error) {
        handle(error)
    }

    private func accept(_ session: ProviderSession) async throws {
        let adult = try await provider.resolveApplicationUser(for: session)
        guard let association = associations.association(for: adult.userID) else {
            state = .needsAssociation(adult, interrupted: false)
            return
        }
        if association.status == .pending {
            state = .needsAssociation(adult, interrupted: true)
        } else if association.profileID == profiles.activeProfileID {
            state = .authenticated(adult, association)
        } else {
            state = .profileSwitchRequired(adult, association, activated: false)
        }
    }

    private func associate(adult: AuthenticatedAdult, profileID: LocalProfileID) {
        do {
            try associations.begin(accountUserID: adult.userID, profileID: profileID)
            let association = try associations.complete(accountUserID: adult.userID)
            applyCompleted(association, to: adult)
            message = "Profile connected. Your data is still stored only on this device."
        } catch {
            message = error.localizedDescription
        }
    }

    private func applyCompleted(_ association: LocalProfileAssociation, to adult: AuthenticatedAdult) {
        if association.profileID == profiles.activeProfileID {
            state = .authenticated(adult, association)
        } else {
            state = .profileSwitchRequired(adult, association, activated: false)
        }
    }

    private func blankWidgetsBeforeProfileSwitch(to profileID: LocalProfileID) {
        widgetGroup?.removeObject(forKey: WidgetSnapshot.storageKey(profileID: profileID.rawValue))
        widgetGroup?.removeObject(forKey: HabitWidgetSnapshot.storageKey(profileID: profileID.rawValue))
        widgetGroup?.set(profileID.rawValue, forKey: WidgetSnapshot.activeProfileKey)
    }

    private func handle(_ error: Error) {
        let accountError = error as? AccountAuthenticationError
        switch accountError {
        case .expired:
            state = .sessionExpired
        case .revoked:
            state = .sessionRevoked
        case .cancelled:
            break
        default:
            if case .restoring = state { state = .signedOut }
            message = error.localizedDescription
        }
    }
}

struct UnconfiguredAuthenticationProvider: AdultAuthenticationProvider {
    let isConfigured = false
    func restoreSession() async throws -> ProviderSession? { nil }
    func signInWithApple(_ credential: AppleIdentityCredential) async throws -> ProviderSession {
        throw AccountAuthenticationError.notConfigured
    }
    func resolveApplicationUser(for session: ProviderSession) async throws -> AuthenticatedAdult {
        throw AccountAuthenticationError.notConfigured
    }
    func signOut() async throws {}
}
