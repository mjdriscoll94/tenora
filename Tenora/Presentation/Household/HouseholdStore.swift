import Foundation
import Security

protocol HouseholdInvitationLinkStorage {
    func load() -> [CreatedHouseholdInvitation]
    func save(_ invitation: CreatedHouseholdInvitation) throws
    func remove(id: UUID)
}

struct KeychainHouseholdInvitationLinkStorage: HouseholdInvitationLinkStorage {
    private let service = "com.tenora.app.household-invitations"
    private let account = "created-invitation-links"

    func load() -> [CreatedHouseholdInvitation] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records.map(\.invitation)
    }

    func save(_ invitation: CreatedHouseholdInvitation) throws {
        var invitations = load().filter { $0.id != invitation.id }
        invitations.append(invitation)
        try write(invitations)
    }

    func remove(id: UUID) {
        let remaining = load().filter { $0.id != id }
        if remaining.isEmpty {
            SecItemDelete(baseQuery as CFDictionary)
        } else {
            try? write(remaining)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func write(_ invitations: [CreatedHouseholdInvitation]) throws {
        let data = try JSONEncoder().encode(invitations.map(Record.init))
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
        var attributes = baseQuery
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    private struct Record: Codable {
        let id: UUID
        let token: String
        let expiresAt: Date

        init(_ invitation: CreatedHouseholdInvitation) {
            id = invitation.id
            token = invitation.token
            expiresAt = invitation.expiresAt
        }

        var invitation: CreatedHouseholdInvitation {
            CreatedHouseholdInvitation(id: id, token: token, expiresAt: expiresAt)
        }
    }
}

@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var household: HouseholdSnapshot?
    @Published private(set) var invitationPreview: HouseholdInvitationPreview?
    @Published private(set) var latestInvitation: CreatedHouseholdInvitation?
    @Published private(set) var invitationLinks: [UUID: CreatedHouseholdInvitation] = [:]
    @Published private(set) var isWorking = false
    @Published var message: String?

    let isConfigured: Bool
    private let service: any HouseholdService
    private let linkStorage: any HouseholdInvitationLinkStorage
    private var adult: AuthenticatedAdult?

    init(
        service: any HouseholdService,
        linkStorage: any HouseholdInvitationLinkStorage = KeychainHouseholdInvitationLinkStorage()
    ) {
        self.service = service
        self.linkStorage = linkStorage
        isConfigured = service.isConfigured
    }

    func refresh(for adult: AuthenticatedAdult?) async {
        self.adult = adult
        invitationPreview = nil
        latestInvitation = nil
        invitationLinks = [:]
        guard let adult else {
            household = nil
            message = nil
            return
        }
        await perform {
            household = try await service.fetchHousehold(for: adult)
            reconcileInvitationLinks()
        }
    }

    func createHousehold(name: String) async {
        guard let adult else { message = HouseholdServiceError.signInRequired.localizedDescription; return }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(normalized.count) else {
            message = HouseholdServiceError.invalidName.localizedDescription
            return
        }
        await perform {
            household = try await service.createHousehold(named: normalized, for: adult)
            message = "Household created. Your existing tasks, habits, schedule, and settings are still private."
        }
    }

    func createInvitation(email: String?, role: HouseholdRole) async {
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            let invitation = try await service.createInvitation(
                email: normalizedEmail?.isEmpty == true ? nil : normalizedEmail,
                role: role
            )
            latestInvitation = invitation
            invitationLinks[invitation.id] = invitation
            try? linkStorage.save(invitation)
            if let adult { household = try await service.fetchHousehold(for: adult) }
            reconcileInvitationLinks()
            message = "Invitation ready to share. It expires in 7 days and can be used once."
        }
    }

    func previewInvitation(_ input: String) async {
        guard let token = Self.invitationToken(from: input) else {
            invitationPreview = nil
            message = HouseholdServiceError.invalidInvitation.localizedDescription
            return
        }
        await perform {
            invitationPreview = try await service.previewInvitation(token: token)
            if invitationPreview == nil { message = HouseholdServiceError.invalidInvitation.localizedDescription }
        }
    }

    func acceptInvitation(_ input: String) async {
        guard let adult else { message = HouseholdServiceError.signInRequired.localizedDescription; return }
        guard let token = Self.invitationToken(from: input) else {
            message = HouseholdServiceError.invalidInvitation.localizedDescription
            return
        }
        await perform {
            household = try await service.acceptInvitation(token: token, for: adult)
            invitationPreview = nil
            message = "You joined the household. Your personal Tenora data remains private."
        }
    }

    func revokeInvitation(_ invitation: HouseholdInvitation) async {
        await perform {
            try await service.revokeInvitation(id: invitation.id)
            if let adult { household = try await service.fetchHousehold(for: adult) }
            if latestInvitation?.id == invitation.id { latestInvitation = nil }
            invitationLinks[invitation.id] = nil
            linkStorage.remove(id: invitation.id)
            message = "Invitation revoked."
        }
    }

    func leaveHousehold() async {
        guard adult != nil else {
            message = HouseholdServiceError.signInRequired.localizedDescription
            return
        }
        await perform {
            try await service.leaveHousehold()
            invitationLinks.keys.forEach { linkStorage.remove(id: $0) }
            household = nil
            invitationPreview = nil
            latestInvitation = nil
            invitationLinks = [:]
            message = "You left the household. Your personal Tenora data is unchanged."
        }
    }

    func closeHousehold() async {
        guard adult != nil else {
            message = HouseholdServiceError.signInRequired.localizedDescription
            return
        }
        await perform {
            try await service.closeHousehold()
            invitationLinks.keys.forEach { linkStorage.remove(id: $0) }
            household = nil
            invitationPreview = nil
            latestInvitation = nil
            invitationLinks = [:]
            message = "Household closed. Everyone's personal Tenora data is unchanged."
        }
    }

    func shareableInvitation(for invitation: HouseholdInvitation) -> CreatedHouseholdInvitation? {
        invitationLinks[invitation.id]
    }

    static func invitationToken(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.lowercased() == "tenora", url.host?.lowercased() == "household" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0].lowercased() == "invite" {
                return validToken(parts[1])
            }
        }
        return validToken(trimmed)
    }

    private static func validToken(_ value: String) -> String? {
        let token = value.lowercased()
        guard token.count == 64, token.allSatisfy({ $0.isHexDigit }) else { return nil }
        return token
    }

    private func reconcileInvitationLinks() {
        guard let household else {
            latestInvitation = nil
            invitationLinks = [:]
            return
        }

        var available = Dictionary(uniqueKeysWithValues: linkStorage.load().map { ($0.id, $0) })
        invitationLinks.forEach { available[$0.key] = $0.value }
        let now = Date()
        let pendingIDs = Set(household.invitations.compactMap { invitation in
            invitation.status == .pending && invitation.expiresAt > now ? invitation.id : nil
        })
        invitationLinks = available.filter { pendingIDs.contains($0.key) }
        latestInvitation = invitationLinks.values.max { $0.expiresAt < $1.expiresAt }

        for invitation in household.invitations where !pendingIDs.contains(invitation.id) {
            linkStorage.remove(id: invitation.id)
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            message = error.localizedDescription
        }
    }
}
