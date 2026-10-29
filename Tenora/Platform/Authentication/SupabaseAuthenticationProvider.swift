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
            let _: Bool = try await client
                .rpc("expire_household_ownership_transfer")
                .execute()
                .value
            let households: [HouseholdRow] = try await client
                .from("households")
                .select("id,name")
                .limit(1)
                .execute()
                .value

            let profiles: [AccountProfileRow] = try await client
                .from("account_profiles")
                .select("user_id,display_name")
                .execute()
                .value
            let names = Dictionary(uniqueKeysWithValues: profiles.compactMap { profile in
                profile.displayName.map { (profile.userID, $0) }
            })
            guard let household = households.first else { return nil }

            let memberships: [MembershipRow] = try await client
                .from("household_memberships")
                .select("id,user_id,role,status,joined_at")
                .eq("household_id", value: household.id)
                .order("joined_at", ascending: true)
                .execute()
                .value

            let transfers: [OwnershipTransferRow] = try await client
                .from("household_ownership_transfers")
                .select("id,household_id,requested_by,recipient_user_id,status,expires_at,created_at")
                .eq("household_id", value: household.id)
                .eq("status", value: HouseholdOwnershipTransferStatus.pending.rawValue)
                .limit(1)
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
                memberships: memberships.map { $0.model(displayName: names[$0.userID]) },
                invitations: invitations.map(\.model),
                ownershipTransfer: transfers.first?.model
            )
        } catch {
            throw householdError(error, fallback: "Tenora couldn't load your household. Please try again.")
        }
    }

    func createHousehold(named name: String, memberName: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(normalizedName.count) else { throw HouseholdServiceError.invalidName }
        try await setMemberName(memberName)
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

    func acceptInvitation(token: String, memberName: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        do {
            let rows: [AcceptedHouseholdRow] = try await client
                .rpc(
                    "accept_household_invitation",
                    params: AcceptInvitationParameters(token: token, displayName: memberName)
                )
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

    func setMemberName(_ name: String) async throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(normalized.count) else { throw HouseholdServiceError.invalidMemberName }
        do {
            let _: String = try await client
                .rpc("set_household_member_name", params: MemberNameParameters(displayName: normalized))
                .execute()
                .value
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: "Tenora couldn't save your name. Please try again.")
        }
    }

    func requestOwnershipTransfer(to recipientUserID: UUID) async throws {
        try await runOwnershipCommand(
            "request_household_ownership_transfer",
            params: RecipientParameters(recipientUserID: recipientUserID),
            fallback: "Tenora couldn't request that ownership transfer. Please try again."
        )
    }

    func cancelOwnershipTransfer(id: UUID) async throws {
        try await runOwnershipCommand(
            "cancel_household_ownership_transfer",
            params: TransferParameters(transferID: id),
            fallback: "Tenora couldn't cancel that ownership transfer. Please refresh and try again."
        )
    }

    func declineOwnershipTransfer(id: UUID) async throws {
        try await runOwnershipCommand(
            "decline_household_ownership_transfer",
            params: TransferParameters(transferID: id),
            fallback: "Tenora couldn't decline that ownership transfer. Please refresh and try again."
        )
    }

    func acceptOwnershipTransfer(id: UUID) async throws {
        try await runOwnershipCommand(
            "accept_household_ownership_transfer",
            params: TransferParameters(transferID: id),
            fallback: "Tenora couldn't accept that ownership transfer. Please refresh and try again."
        )
    }

    private func runOwnershipCommand<Parameters: Encodable>(
        _ function: String,
        params: Parameters,
        fallback: String
    ) async throws {
        do {
            let didChange: Bool = try await client.rpc(function, params: params).execute().value
            guard didChange else {
                throw HouseholdServiceError.service("That ownership transfer is no longer pending. Household details were refreshed.")
            }
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: fallback)
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

    func leaveHousehold() async throws {
        do {
            let didLeave: Bool = try await client
                .rpc("leave_household")
                .execute()
                .value
            guard didLeave else {
                throw HouseholdServiceError.service("You are not an active member of a household.")
            }
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: "Tenora couldn't leave the household. Please try again.")
        }
    }

    func closeHousehold() async throws {
        do {
            let didClose: Bool = try await client
                .rpc("close_household")
                .execute()
                .value
            guard didClose else {
                throw HouseholdServiceError.service("This household is no longer active.")
            }
        } catch let error as HouseholdServiceError {
            throw error
        } catch {
            throw householdError(error, fallback: "Tenora couldn't close the household. Please try again.")
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
        if detail.contains("owners must transfer ownership") {
            return .service("Transfer household ownership before leaving.")
        }
        if detail.contains("other active members must leave") {
            return .service("Every other adult must leave before the household can be closed.")
        }
        if detail.contains("household owner permission required") {
            return .service("Only the household owner can close the household.")
        }
        if detail.contains("member name must be") || detail.contains("add your name") {
            return .invalidMemberName
        }
        if detail.contains("already uses that name") {
            return .service("Another adult in this household already uses that name.")
        }
        if detail.contains("already pending") {
            return .service("An ownership transfer is already pending.")
        }
        if detail.contains("both adults must add their names") {
            return .service("Both adults need names before ownership can be transferred.")
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

        func model(displayName: String?) -> HouseholdMembership {
            HouseholdMembership(
                id: id,
                userID: userID,
                role: role,
                status: status,
                joinedAt: joinedAt,
                displayName: displayName
            )
        }

        enum CodingKeys: String, CodingKey {
            case id, role, status
            case userID = "user_id"
            case joinedAt = "joined_at"
        }
    }

    private struct AccountProfileRow: Decodable {
        let userID: UUID
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case displayName = "display_name"
        }
    }

    private struct OwnershipTransferRow: Decodable {
        let id: UUID
        let householdID: UUID
        let requestedBy: UUID
        let recipientUserID: UUID
        let status: HouseholdOwnershipTransferStatus
        let expiresAt: Date
        let createdAt: Date

        var model: HouseholdOwnershipTransfer {
            HouseholdOwnershipTransfer(
                id: id,
                householdID: householdID,
                requestedBy: requestedBy,
                recipientUserID: recipientUserID,
                status: status,
                expiresAt: expiresAt,
                createdAt: createdAt
            )
        }

        enum CodingKeys: String, CodingKey {
            case id, status
            case householdID = "household_id"
            case requestedBy = "requested_by"
            case recipientUserID = "recipient_user_id"
            case expiresAt = "expires_at"
            case createdAt = "created_at"
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

    private struct AcceptInvitationParameters: Encodable {
        let token: String
        let displayName: String
        enum CodingKeys: String, CodingKey {
            case token = "p_invitation_token"
            case displayName = "p_display_name"
        }
    }

    private struct MemberNameParameters: Encodable {
        let displayName: String
        enum CodingKeys: String, CodingKey { case displayName = "p_display_name" }
    }

    private struct RecipientParameters: Encodable {
        let recipientUserID: UUID
        enum CodingKeys: String, CodingKey { case recipientUserID = "p_recipient_user_id" }
    }

    private struct TransferParameters: Encodable {
        let transferID: UUID
        enum CodingKeys: String, CodingKey { case transferID = "p_transfer_id" }
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
