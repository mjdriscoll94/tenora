import Foundation

protocol HouseholdService: Sendable {
    var isConfigured: Bool { get }
    func fetchHousehold(for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot?
    func createHousehold(named name: String, memberName: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot
    func createInvitation(email: String?, role: HouseholdRole) async throws -> CreatedHouseholdInvitation
    func previewInvitation(token: String) async throws -> HouseholdInvitationPreview?
    func acceptInvitation(token: String, memberName: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot
    func setMemberName(_ name: String) async throws
    func revokeInvitation(id: UUID) async throws
    func requestOwnershipTransfer(to recipientUserID: UUID) async throws
    func cancelOwnershipTransfer(id: UUID) async throws
    func declineOwnershipTransfer(id: UUID) async throws
    func acceptOwnershipTransfer(id: UUID) async throws
    func leaveHousehold() async throws
    func closeHousehold() async throws
}

struct UnconfiguredHouseholdService: HouseholdService {
    let isConfigured = false

    func fetchHousehold(for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot? { nil }
    func createHousehold(named name: String, memberName: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        throw HouseholdServiceError.notConfigured
    }
    func createInvitation(email: String?, role: HouseholdRole) async throws -> CreatedHouseholdInvitation {
        throw HouseholdServiceError.notConfigured
    }
    func previewInvitation(token: String) async throws -> HouseholdInvitationPreview? {
        throw HouseholdServiceError.notConfigured
    }
    func acceptInvitation(token: String, memberName: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        throw HouseholdServiceError.notConfigured
    }
    func setMemberName(_ name: String) async throws { throw HouseholdServiceError.notConfigured }
    func revokeInvitation(id: UUID) async throws { throw HouseholdServiceError.notConfigured }
    func requestOwnershipTransfer(to recipientUserID: UUID) async throws { throw HouseholdServiceError.notConfigured }
    func cancelOwnershipTransfer(id: UUID) async throws { throw HouseholdServiceError.notConfigured }
    func declineOwnershipTransfer(id: UUID) async throws { throw HouseholdServiceError.notConfigured }
    func acceptOwnershipTransfer(id: UUID) async throws { throw HouseholdServiceError.notConfigured }
    func leaveHousehold() async throws { throw HouseholdServiceError.notConfigured }
    func closeHousehold() async throws { throw HouseholdServiceError.notConfigured }
}
