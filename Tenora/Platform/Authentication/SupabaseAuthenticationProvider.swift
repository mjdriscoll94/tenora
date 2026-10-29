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

final class SupabaseAuthenticationProvider: AdultAuthenticationProvider, HouseholdService {
    let isConfigured = true
    private let client: SupabaseClient
    var householdService: any HouseholdService { self }

    init(configuration: SupabaseAccountConfiguration) {
        // Supabase's supported Apple-platform default stores the session in Keychain.
        // Only the publishable client key is embedded in the app; service-role secrets
        // must never be provided here.
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
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

    func fetchHousehold(for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot? {
        do {
            let households: [HouseholdRow] = try await client
                .from("households")
                .select("id,name")
                .limit(1)
                .execute()
                .value
            guard let household = households.first else { return nil }

            let memberships: [MembershipRow] = try await client
                .from("household_memberships")
                .select("id,user_id,role,status,joined_at")
                .eq("household_id", value: household.id)
                .order("joined_at", ascending: true)
                .execute()
                .value

            let invitations: [InvitationRow] = try await client
                .from("household_invitations")
                .select("id,recipient_email,role,status,expires_at")
                .eq("household_id", value: household.id)
                .eq("status", value: HouseholdInvitationStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            return HouseholdSnapshot(
                id: household.id,
                name: household.name,
                currentUserID: adult.userID,
                memberships: memberships.map(\.model),
                invitations: invitations.map(\.model)
            )
        } catch {
            throw householdError(error, fallback: "Tenora couldn't load your household. Please try again.")
        }
    }

    func createHousehold(named name: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(normalizedName.count) else { throw HouseholdServiceError.invalidName }
        do {
            // Do not request the inserted row here. The owner's membership is created
            // by an AFTER INSERT trigger, and the household SELECT policy depends on
            // that membership. Asking PostgREST for a representation evaluates the
            // SELECT policy before the trigger-created membership is visible and rolls
            // the otherwise-valid insert back under RLS.
            try await client
                .from("households")
                .insert(CreateHouseholdPayload(name: normalizedName, createdBy: adult.userID))
                .execute()
            guard let household = try await fetchHousehold(for: adult) else {
                throw HouseholdServiceError.service("The household was created, but Tenora couldn't reload it.")
            }
            return household
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: "Tenora couldn't create the household. Please try again.")
        }
    }

    func createInvitation(email: String?, role: HouseholdRole) async throws -> CreatedHouseholdInvitation {
        do {
            let rows: [CreatedInvitationRow] = try await client
                .rpc(
                    "create_household_invitation",
                    params: CreateInvitationParameters(
                        recipientEmail: email?.trimmingCharacters(in: .whitespacesAndNewlines),
                        role: role.rawValue,
                        expiresInHours: 168
                    )
                )
                .execute()
                .value
            guard let row = rows.first else {
                throw HouseholdServiceError.service("Tenora didn't receive an invitation code. Please try again.")
            }
            return CreatedHouseholdInvitation(id: row.id, token: row.token, expiresAt: row.expiresAt)
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: "Tenora couldn't create that invitation. Please try again.")
        }
    }

    func previewInvitation(token: String) async throws -> HouseholdInvitationPreview? {
        do {
            let rows: [InvitationPreviewRow] = try await client
                .rpc("preview_household_invitation", params: InvitationTokenParameters(token: token))
                .execute()
                .value
            return rows.first?.model
        } catch {
            throw householdError(error, fallback: "Tenora couldn't check that invitation. Please try again.")
        }
    }

    func acceptInvitation(token: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        do {
            let rows: [AcceptedHouseholdRow] = try await client
                .rpc("accept_household_invitation", params: InvitationTokenParameters(token: token))
                .execute()
                .value
            guard !rows.isEmpty, let household = try await fetchHousehold(for: adult) else {
                throw HouseholdServiceError.service("The invitation was accepted, but Tenora couldn't reload the household.")
            }
            return household
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: "Tenora couldn't accept that invitation. Please try again.")
        }
    }

    func revokeInvitation(id: UUID) async throws {
        do {
            let _: Bool = try await client
                .rpc("revoke_household_invitation", params: RevokeInvitationParameters(id: id))
                .execute()
                .value
        } catch {
            throw householdError(error, fallback: "Tenora couldn't revoke that invitation. Please try again.")
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

    private func householdError(_ error: Error, fallback: String) -> HouseholdServiceError {
        let detail = "\(error)".lowercased()
        if detail.contains("jwt") || detail.contains("session") || detail.contains("authentication required") {
            return .signInRequired
        }
        if detail.contains("invitation is invalid") {
            return .invalidInvitation
        }
        if detail.contains("invitation has expired") {
            return .service("That invitation has expired. Ask a household manager for a new one.")
        }
        if detail.contains("invitation is no longer available") {
            return .service("That invitation has already been used or revoked.")
        }
        if detail.contains("current household") {
            return .service("Leave your current household before joining another one.")
        }
        if detail.contains("row-level security") || detail.contains("42501") {
            return .service("Tenora couldn't verify your household access. Sign out, sign back in, and try again.")
        }
        if detail.contains("pending_email") || detail.contains("duplicate key") {
            return .service("There is already an active invitation for that email address.")
        }
        return .service(fallback)
    }

    private struct HouseholdRow: Decodable {
        let id: UUID
        let name: String
    }

    private struct MembershipRow: Decodable {
        let id: UUID
        let userID: UUID
        let role: HouseholdRole
        let status: HouseholdMembershipStatus
        let joinedAt: Date

        var model: HouseholdMembership {
            HouseholdMembership(id: id, userID: userID, role: role, status: status, joinedAt: joinedAt)
        }

        enum CodingKeys: String, CodingKey {
            case id, role, status
            case userID = "user_id"
            case joinedAt = "joined_at"
        }
    }

    private struct InvitationRow: Decodable {
        let id: UUID
        let recipientEmail: String?
        let role: HouseholdRole
        let status: HouseholdInvitationStatus
        let expiresAt: Date

        var model: HouseholdInvitation {
            HouseholdInvitation(id: id, recipientEmail: recipientEmail, role: role, status: status, expiresAt: expiresAt)
        }

        enum CodingKeys: String, CodingKey {
            case id, role, status
            case recipientEmail = "recipient_email"
            case expiresAt = "expires_at"
        }
    }

    private struct CreateHouseholdPayload: Encodable {
        let name: String
        let createdBy: UUID

        enum CodingKeys: String, CodingKey {
            case name
            case createdBy = "created_by"
        }
    }

    private struct CreateInvitationParameters: Encodable {
        let recipientEmail: String?
        let role: String
        let expiresInHours: Int

        enum CodingKeys: String, CodingKey {
            case recipientEmail = "p_recipient_email"
            case role = "p_role"
            case expiresInHours = "p_expires_in_hours"
        }
    }

    private struct InvitationTokenParameters: Encodable {
        let token: String
        enum CodingKeys: String, CodingKey { case token = "p_invitation_token" }
    }

    private struct RevokeInvitationParameters: Encodable {
        let id: UUID
        enum CodingKeys: String, CodingKey { case id = "p_invitation_id" }
    }

    private struct CreatedInvitationRow: Decodable {
        let id: UUID
        let token: String
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case id = "invitation_id"
            case token = "invitation_token"
            case expiresAt = "invitation_expires_at"
        }
    }

    private struct InvitationPreviewRow: Decodable {
        let householdName: String
        let role: HouseholdRole
        let expiresAt: Date
        let status: HouseholdInvitationStatus

        var model: HouseholdInvitationPreview {
            HouseholdInvitationPreview(householdName: householdName, role: role, expiresAt: expiresAt, status: status)
        }

        enum CodingKeys: String, CodingKey {
            case householdName = "household_name"
            case role = "invited_role"
            case expiresAt = "invitation_expires_at"
            case status = "invitation_status"
        }
    }

    private struct AcceptedHouseholdRow: Decodable {
        let householdID: UUID
        enum CodingKeys: String, CodingKey { case householdID = "household_id" }
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
