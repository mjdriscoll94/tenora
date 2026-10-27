import Foundation

protocol AdultAuthenticationProvider {
    var isConfigured: Bool { get }
    var householdService: any HouseholdService { get }
    func restoreSession() async throws -> ProviderSession?
    func signInWithApple(_ credential: AppleIdentityCredential) async throws -> ProviderSession
    func resolveApplicationUser(for session: ProviderSession) async throws -> AuthenticatedAdult
    func signOut() async throws
}

extension AdultAuthenticationProvider {
    var householdService: any HouseholdService { UnconfiguredHouseholdService() }
}

@MainActor
protocol ProfileAssociationRepository: AnyObject {
    func association(for accountUserID: UUID) -> LocalProfileAssociation?
    func association(for profileID: LocalProfileID) -> LocalProfileAssociation?
    func begin(accountUserID: UUID, profileID: LocalProfileID) throws
    func complete(accountUserID: UUID) throws -> LocalProfileAssociation
    func removePending(accountUserID: UUID)
}
