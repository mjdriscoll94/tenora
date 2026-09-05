import Foundation

enum TenoraRoute: Equatable {
    case capture(String)
    case task(UUID)
    case today

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
        default: return nil
        }
    }
}
