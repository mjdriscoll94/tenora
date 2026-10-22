import Foundation

/// A signed-in adult is intentionally distinct from a local data profile and from
/// future household memberships or managed child profiles.
struct AuthenticatedAdult: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable {
        case supabase
    }

    let userID: UUID
    let provider: Provider
    let providerSubject: String
    let email: String?
}

struct ProviderSession: Equatable, Sendable {
    let providerSubject: String
    let email: String?
}

struct AppleIdentityCredential: Equatable, Sendable {
    let identityToken: String
    let rawNonce: String
}

enum AccountAuthenticationError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case cancelled
    case expired
    case revoked
    case networkUnavailable
    case invalidCredential
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Account sign-in is not configured in this build. You can keep using Tenora locally."
        case .cancelled:
            return nil
        case .expired:
            return "Your session expired. Sign in again when you're ready. Your local data is still here."
        case .revoked:
            return "This session was revoked. Sign in again to reconnect this device. Your local data was not removed."
        case .networkUnavailable:
            return "Tenora couldn't reach the account service. Your local tasks and habits are still available."
        case .invalidCredential:
            return "That sign-in could not be verified. Please try again."
        case .service(let message):
            return message
        }
    }
}

struct LocalProfileAssociation: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case complete
    }

    let accountUserID: UUID
    let profileID: LocalProfileID
    let status: Status
    let updatedAt: Date
}

enum ProfileAssociationError: LocalizedError, Equatable {
    case profileAlreadyAssociated
    case missingPendingAssociation

    var errorDescription: String? {
        switch self {
        case .profileAlreadyAssociated:
            return "This local profile is already connected to a different Tenora account. Start a separate profile instead."
        case .missingPendingAssociation:
            return "Tenora couldn't finish that profile connection. Please try again."
        }
    }
}
