import Foundation
import Supabase

struct SupabaseAccountConfiguration: Equatable {
    let url: URL
    let publishableKey: String

    init?(bundle: Bundle = .main) {
        guard
            let rawURL = bundle.object(forInfoDictionaryKey: "TENORA_SUPABASE_URL") as? String,
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https",
            url.host != nil,
            let rawKey = bundle.object(forInfoDictionaryKey: "TENORA_SUPABASE_PUBLISHABLE_KEY") as? String
        else { return nil }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("$(") else { return nil }
        self.url = url
        publishableKey = key
    }
}

final class SupabaseAuthenticationProvider: AdultAuthenticationProvider {
    let isConfigured = true
    private let client: SupabaseClient

    init(configuration: SupabaseAccountConfiguration) {
        // Supabase's supported Apple-platform default stores the session in Keychain.
        // Only the publishable client key is embedded in the app; service-role secrets
        // must never be provided here.
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    func restoreSession() async throws -> ProviderSession? {
        guard client.auth.currentSession != nil else { return nil }
        do {
            return providerSession(try await client.auth.session)
        } catch {
            throw classify(error, restoring: true)
        }
    }

    func signInWithApple(_ credential: AppleIdentityCredential) async throws -> ProviderSession {
        do {
            let session = try await client.auth.signInWithIdToken(credentials: .init(
                provider: .apple,
                idToken: credential.identityToken,
                nonce: credential.rawNonce
            ))
            return providerSession(session)
        } catch {
            throw classify(error, restoring: false)
        }
    }

    func resolveApplicationUser(for session: ProviderSession) async throws -> AuthenticatedAdult {
        guard client.auth.currentSession?.user.id.uuidString == session.providerSubject else {
            throw AccountAuthenticationError.revoked
        }
        do {
            let identity: IdentityRow = try await client
                .from("user_identities")
                .select("user_id")
                .single()
                .execute()
                .value
            return AuthenticatedAdult(
                userID: identity.userID,
                provider: .supabase,
                providerSubject: session.providerSubject,
                email: session.email
            )
        } catch {
            throw classify(error, restoring: false)
        }
    }

    private struct IdentityRow: Decodable {
        let userID: UUID

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            // The supported client removes the local Keychain session before making
            // the revocation request. If it is gone, this device is safely signed out.
            guard client.auth.currentSession != nil else { return }
            throw classify(error, restoring: false)
        }
    }

    private func providerSession(_ session: Session) -> ProviderSession {
        ProviderSession(providerSubject: session.user.id.uuidString, email: session.user.email)
    }

    private func classify(_ error: Error, restoring: Bool) -> AccountAuthenticationError {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(urlError.code) {
            return .networkUnavailable
        }
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .sessionNotFound, .refreshTokenNotFound, .refreshTokenAlreadyUsed, .userNotFound:
                return .revoked
            case .badJWT, .invalidJWT:
                return restoring ? .expired : .invalidCredential
            default:
                return restoring ? .expired : .invalidCredential
            }
        }
        return .service("Tenora couldn't complete account sign-in. Your local data was not changed.")
    }
}

enum AccountProviderFactory {
    static func make(bundle: Bundle = .main) -> AdultAuthenticationProvider {
        guard let configuration = SupabaseAccountConfiguration(bundle: bundle) else {
            return UnconfiguredAuthenticationProvider()
        }
        return SupabaseAuthenticationProvider(configuration: configuration)
    }
}
