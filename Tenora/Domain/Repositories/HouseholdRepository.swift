import Foundation

protocol HouseholdService: Sendable {
    var isConfigured: Bool { get }
    func fetchHousehold(for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot?
    func createHousehold(named name: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot
    func createInvitation(email: String?, role: HouseholdRole) async throws -> CreatedHouseholdInvitation
    func previewInvitation(token: String) async throws -> HouseholdInvitationPreview?
    func acceptInvitation(token: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot
    func revokeInvitation(id: UUID) async throws
}

struct UnconfiguredHouseholdService: HouseholdService {
    let isConfigured = false

    func fetchHousehold(for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot? { nil }
    func createHousehold(named name: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        throw HouseholdServiceError.notConfigured
    }
    func createInvitation(email: String?, role: HouseholdRole) async throws -> CreatedHouseholdInvitation {
        throw HouseholdServiceError.notConfigured
    }
    func previewInvitation(token: String) async throws -> HouseholdInvitationPreview? {
        throw HouseholdServiceError.notConfigured
    }
    func acceptInvitation(token: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        throw HouseholdServiceError.notConfigured
    }
    func revokeInvitation(id: UUID) async throws { throw HouseholdServiceError.notConfigured }
}
