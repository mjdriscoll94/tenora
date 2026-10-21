import Foundation

struct LocalProfileID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    static let offline = LocalProfileID(rawValue: "offline")

    let rawValue: String

    init(rawValue: String) {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = cleaned.isEmpty ? Self.offline.rawValue : cleaned
    }

    var description: String { rawValue }

    var storageComponent: String {
        if self == .offline { return Self.offline.rawValue }
        // Base64url is reversible and collision-free; replacing punctuation with an
        // underscore could otherwise make two provider subjects share one local store.
        return "p_" + Data(rawValue.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
