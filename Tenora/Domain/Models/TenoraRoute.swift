import Foundation

enum TenoraRoute: Equatable {
    case capture(String)
    case task(UUID)
    case today
    case habits
    case habit(UUID)
    case householdInvitation(String)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "tenora" else { return nil }
        switch url.host {
        case "add":
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "title" }?.value ?? ""
            self = .capture(String(text.prefix(2000)))
        case "task":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .task(id)
        case "today": self = .today
        case "habits": self = .habits
        case "habit":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .habit(id)
        case "household":
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2,
                  parts[0].lowercased() == "invite",
                  let token = Self.householdInvitationToken(parts[1])
            else { return nil }
            self = .householdInvitation(token)
        default: return nil
        }
    }

    private static func householdInvitationToken(_ value: String) -> String? {
        let token = value.lowercased()
        guard token.count == 64, token.allSatisfy({ $0.isHexDigit }) else { return nil }
        return token
    }
}
