import XCTest
@testable import Tenora

@MainActor
final class AccountFoundationTests: XCTestCase {
    private let adultA = AuthenticatedAdult(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        provider: .supabase,
        providerSubject: "auth-a",
        email: "a@example.com"
    )

    func testShippedAppBundleContainsSupabaseAccountConfiguration() {
        let configuration = SupabaseAccountConfiguration(bundle: .main)

        XCTAssertEqual(configuration?.url.absoluteString, "https://hcwtsntljmpbkgzclnxs.supabase.co")
        XCTAssertTrue(configuration?.publishableKey.hasPrefix("sb_publishable_") == true)
    }

    func testNoSessionRestoresToSignedOutWithoutChangingProfile() async {
        let provider = FakeAuthenticationProvider(session: nil, adult: adultA)
        let profiles = TestProfileRepository()
        let store = makeStore(provider: provider, profiles: profiles)

        await store.restore()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(profiles.activeProfileID, .offline)
    }

    func testNewSignInRequiresExplicitLocalProfileAssociation() async {
        let provider = FakeAuthenticationProvider(session: nil, adult: adultA)
        let store = makeStore(provider: provider)

        await store.signInWithApple(identityToken: "token", rawNonce: "nonce")

        XCTAssertEqual(store.state, .needsAssociation(adultA, interrupted: false))
    }

    func testAssociationPreservesExistingOfflineProfileAndDoesNotSwitchIt() async {
        let provider = FakeAuthenticationProvider(session: nil, adult: adultA)
        let profiles = TestProfileRepository()
        let store = makeStore(provider: provider, profiles: profiles)
        await store.signInWithApple(identityToken: "token", rawNonce: "nonce")

        store.associateCurrentProfile()

        let expected = LocalProfileAssociation(
            accountUserID: adultA.userID,
            profileID: .offline,
            status: .complete,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(store.state, .authenticated(adultA, expected))
        XCTAssertEqual(profiles.activeProfileID, .offline)
    }

    func testInterruptedAssociationIsDetectedAndCanBeRetried() async throws {
        let defaults = isolatedDefaults()
        let associations = UserDefaultsProfileAssociationRepository(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        try associations.begin(accountUserID: adultA.userID, profileID: .offline)
        let provider = FakeAuthenticationProvider(session: ProviderSession(providerSubject: "auth-a", email: nil), adult: adultA)
        let store = AccountStore(provider: provider, associations: associations, profiles: TestProfileRepository(), widgetGroup: nil)

        await store.restore()
        XCTAssertEqual(store.state, .needsAssociation(adultA, interrupted: true))

        store.finishInterruptedAssociation()
        guard case .authenticated = store.state else { return XCTFail("Expected completed association") }
    }

    func testInterruptedSeparateProfileKeepsItsOriginalTarget() async throws {
        let defaults = isolatedDefaults()
        let target = LocalProfileID(rawValue: "account.interrupted")
        let associations = UserDefaultsProfileAssociationRepository(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        try associations.begin(accountUserID: adultA.userID, profileID: target)
        let provider = FakeAuthenticationProvider(session: ProviderSession(providerSubject: "auth-a", email: nil), adult: adultA)
        let store = AccountStore(provider: provider, associations: associations, profiles: TestProfileRepository(), widgetGroup: nil)
        await store.restore()

        store.finishInterruptedAssociation()

        guard case .profileSwitchRequired(_, let association, false) = store.state else {
            return XCTFail("Expected switch to the original pending profile")
        }
        XCTAssertEqual(association.profileID, target)
    }

    func testOneLocalProfileCannotBeConnectedToTwoAccounts() throws {
        let defaults = isolatedDefaults()
        let repository = UserDefaultsProfileAssociationRepository(defaults: defaults)
        try repository.begin(accountUserID: adultA.userID, profileID: .offline)
        _ = try repository.complete(accountUserID: adultA.userID)

        XCTAssertThrowsError(try repository.begin(accountUserID: UUID(), profileID: .offline)) { error in
            XCTAssertEqual(error as? ProfileAssociationError, .profileAlreadyAssociated)
        }
    }

    func testExistingAccountOnDifferentProfileRequiresProtectedSwitch() async throws {
        let defaults = isolatedDefaults()
        let profileID = LocalProfileID(rawValue: "account.a")
        let associations = UserDefaultsProfileAssociationRepository(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        try associations.begin(accountUserID: adultA.userID, profileID: profileID)
        let completed = try associations.complete(accountUserID: adultA.userID)
        let provider = FakeAuthenticationProvider(session: ProviderSession(providerSubject: "auth-a", email: nil), adult: adultA)
        let profiles = TestProfileRepository()
        let store = AccountStore(provider: provider, associations: associations, profiles: profiles, widgetGroup: nil)

        await store.restore()

        XCTAssertEqual(store.state, .profileSwitchRequired(adultA, completed, activated: false))
        XCTAssertEqual(profiles.activeProfileID, .offline)
    }

    func testExpiredAndRevokedSessionsAreDistinguished() async {
        let expired = FakeAuthenticationProvider(session: nil, adult: adultA, restoreError: .expired)
        let expiredStore = makeStore(provider: expired)
        await expiredStore.restore()
        XCTAssertEqual(expiredStore.state, .sessionExpired)

        let revoked = FakeAuthenticationProvider(session: nil, adult: adultA, restoreError: .revoked)
        let revokedStore = makeStore(provider: revoked)
        await revokedStore.restore()
        XCTAssertEqual(revokedStore.state, .sessionRevoked)
    }

    func testSignOutLeavesLocalProfileActive() async throws {
        let defaults = isolatedDefaults()
        let associations = UserDefaultsProfileAssociationRepository(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        try associations.begin(accountUserID: adultA.userID, profileID: .offline)
        _ = try associations.complete(accountUserID: adultA.userID)
        let provider = FakeAuthenticationProvider(session: ProviderSession(providerSubject: "auth-a", email: nil), adult: adultA)
        let profiles = TestProfileRepository()
        let store = AccountStore(provider: provider, associations: associations, profiles: profiles, widgetGroup: nil)
        await store.restore()

        await store.signOut()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(profiles.activeProfileID, .offline)
        XCTAssertTrue(provider.didSignOut)
    }

    func testUnconfiguredAndUnavailableProvidersKeepLocalUseAvailable() async {
        let localStore = AccountStore(
            provider: UnconfiguredAuthenticationProvider(),
            associations: UserDefaultsProfileAssociationRepository(defaults: isolatedDefaults()),
            profiles: TestProfileRepository(),
            widgetGroup: nil
        )
        await localStore.restore()
        XCTAssertEqual(localStore.state, .localOnly)

        let unavailable = FakeAuthenticationProvider(
            session: ProviderSession(providerSubject: "auth-a", email: nil),
            adult: adultA,
            restoreError: .networkUnavailable
        )
        let unavailableStore = makeStore(provider: unavailable)
        await unavailableStore.restore()
        XCTAssertEqual(unavailableStore.state, .signedOut)
        XCTAssertNotNil(unavailableStore.message)
    }

    func testCancelledAppleSignInDoesNotShowAnErrorOrChangeState() async {
        let provider = FakeAuthenticationProvider(session: nil, adult: adultA, signInError: .cancelled)
        let store = makeStore(provider: provider)

        await store.signInWithApple(identityToken: "token", rawNonce: "nonce")

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.message)
    }

    func testAccountSwitchRequiresSeparateProfileAndBlanksDestinationWidget() async throws {
        let adultB = AuthenticatedAdult(
            userID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            provider: .supabase,
            providerSubject: "auth-b",
            email: "b@example.com"
        )
        let defaults = isolatedDefaults()
        let widgetDefaults = isolatedDefaults()
        let associations = UserDefaultsProfileAssociationRepository(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        try associations.begin(accountUserID: adultA.userID, profileID: .offline)
        _ = try associations.complete(accountUserID: adultA.userID)
        let profiles = TestProfileRepository()
        let provider = FakeAuthenticationProvider(session: nil, adult: adultB)
        let store = AccountStore(provider: provider, associations: associations, profiles: profiles, widgetGroup: widgetDefaults)

        await store.signInWithApple(identityToken: "token", rawNonce: "nonce")
        XCTAssertEqual(store.state, .needsAssociation(adultB, interrupted: false))

        store.associateCurrentProfile()
        XCTAssertEqual(store.state, .needsAssociation(adultB, interrupted: false))
        XCTAssertNotNil(store.message)

        store.associateSeparateProfile()
        guard case .profileSwitchRequired(_, let association, false) = store.state else {
            return XCTFail("Expected protected profile switch")
        }
        widgetDefaults.set(Data("private".utf8), forKey: WidgetSnapshot.storageKey(profileID: association.profileID.rawValue))

        store.activateAssociatedProfile()

        XCTAssertEqual(profiles.activeProfileID, association.profileID)
        XCTAssertNil(widgetDefaults.data(forKey: WidgetSnapshot.storageKey(profileID: association.profileID.rawValue)))
        XCTAssertEqual(widgetDefaults.string(forKey: WidgetSnapshot.activeProfileKey), association.profileID.rawValue)
    }

    private func makeStore(
        provider: FakeAuthenticationProvider,
        profiles: TestProfileRepository? = nil
    ) -> AccountStore {
        AccountStore(
            provider: provider,
            associations: UserDefaultsProfileAssociationRepository(defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 100) }),
            profiles: profiles ?? TestProfileRepository(),
            widgetGroup: nil
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "AccountFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class FakeAuthenticationProvider: AdultAuthenticationProvider {
    let isConfigured = true
    var session: ProviderSession?
    let adult: AuthenticatedAdult
    let restoreError: AccountAuthenticationError?
    let signInError: AccountAuthenticationError?
    var didSignOut = false

    init(
        session: ProviderSession?,
        adult: AuthenticatedAdult,
        restoreError: AccountAuthenticationError? = nil,
        signInError: AccountAuthenticationError? = nil
    ) {
        self.session = session
        self.adult = adult
        self.restoreError = restoreError
        self.signInError = signInError
    }

    func restoreSession() async throws -> ProviderSession? {
        if let restoreError { throw restoreError }
        return session
    }

    func signInWithApple(_ credential: AppleIdentityCredential) async throws -> ProviderSession {
        if let signInError { throw signInError }
        let session = ProviderSession(providerSubject: adult.providerSubject, email: adult.email)
        self.session = session
        return session
    }

    func resolveApplicationUser(for session: ProviderSession) async throws -> AuthenticatedAdult { adult }
    func signOut() async throws { didSignOut = true; session = nil }
}

@MainActor
private final class TestProfileRepository: ProfileRepository {
    private(set) var activeProfileID: LocalProfileID = .offline
    func activate(_ profileID: LocalProfileID) { activeProfileID = profileID }
    func returnToOfflineProfile() { activeProfileID = .offline }
}
