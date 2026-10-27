import Foundation

@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var household: HouseholdSnapshot?
    @Published private(set) var invitationPreview: HouseholdInvitationPreview?
    @Published private(set) var latestInvitation: CreatedHouseholdInvitation?
    @Published private(set) var isWorking = false
    @Published var message: String?

    let isConfigured: Bool
    private let service: any HouseholdService
    private var adult: AuthenticatedAdult?

    init(service: any HouseholdService) {
        self.service = service
        isConfigured = service.isConfigured
    }

    func refresh(for adult: AuthenticatedAdult?) async {
        self.adult = adult
        invitationPreview = nil
        latestInvitation = nil
        guard let adult else {
            household = nil
            message = nil
            return
        }
        await perform { household = try await service.fetchHousehold(for: adult) }
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
            latestInvitation = try await service.createInvitation(
                email: normalizedEmail?.isEmpty == true ? nil : normalizedEmail,
                role: role
            )
            if let adult { household = try await service.fetchHousehold(for: adult) }
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
            message = "Invitation revoked."
        }
    }

    func dismissGeneratedInvitation() { latestInvitation = nil }

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
