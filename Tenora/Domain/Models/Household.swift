import Foundation

enum HouseholdRole: String, Codable, CaseIterable, Sendable {
    case owner
    case admin
    case adult

    var displayName: String { rawValue.capitalized }
    var canManageInvitations: Bool { self == .owner || self == .admin }
}

enum HouseholdMembershipStatus: String, Codable, Sendable {
    case active
    case left
    case revoked
}

enum HouseholdInvitationStatus: String, Codable, Sendable {
    case pending
    case accepted
    case revoked
    case expired
}

enum HouseholdOwnershipTransferStatus: String, Codable, Sendable {
    case pending
    case accepted
    case cancelled
    case declined
    case expired
}

struct HouseholdMembership: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let role: HouseholdRole
    let status: HouseholdMembershipStatus
    let joinedAt: Date
    let displayName: String?
}

struct HouseholdOwnershipTransfer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let householdID: UUID
    let requestedBy: UUID
    let recipientUserID: UUID
    let status: HouseholdOwnershipTransferStatus
    let expiresAt: Date
    let createdAt: Date

    var isPending: Bool { status == .pending && expiresAt > Date() }
}

struct HouseholdInvitation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let recipientEmail: String?
    let role: HouseholdRole
    let status: HouseholdInvitationStatus
    let expiresAt: Date
}

struct HouseholdSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let currentUserID: UUID
    let memberships: [HouseholdMembership]
    let invitations: [HouseholdInvitation]
    let ownershipTransfer: HouseholdOwnershipTransfer?

    var currentMembership: HouseholdMembership? {
        memberships.first { $0.userID == currentUserID && $0.status == .active }
    }

    var currentRole: HouseholdRole? { currentMembership?.role }
    var activeMembers: [HouseholdMembership] { memberships.filter { $0.status == .active } }
    var pendingInvitations: [HouseholdInvitation] { invitations.filter { $0.status == .pending } }

    func memberName(for userID: UUID) -> String {
        memberships.first { $0.userID == userID }?.displayName ?? "Name needed"
    }
}

struct CreatedHouseholdInvitation: Equatable, Sendable {
    let id: UUID
    let token: String
    let expiresAt: Date

    var shareURL: URL? {
        URL(string: "tenora://household/invite/\(token)")
    }
}

struct HouseholdInvitationPreview: Equatable, Sendable {
    let householdName: String
    let role: HouseholdRole
    let expiresAt: Date
    let status: HouseholdInvitationStatus

    var canAccept: Bool { status == .pending && expiresAt > Date() }
}

enum HouseholdServiceError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case signInRequired
    case invalidName
    case invalidMemberName
    case invalidInvitation
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Household connections are not configured in this build."
        case .signInRequired:
            return "Sign in with your adult Tenora account to use a household."
        case .invalidName:
            return "Enter a household name between 1 and 100 characters."
        case .invalidMemberName:
            return "Add your name using 1 to 100 characters."
        case .invalidInvitation:
            return "That invitation code or link is not valid."
        case .service(let message):
            return message
        }
    }
}
