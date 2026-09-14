import Foundation
import Security

struct AgentBridgeTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

struct AgentBridgeTokenStore: Sendable {
    private let service = "com.tenora.app.agent-bridge"
    private let account = "oauth-access-token"

    func load() -> AgentBridgeTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AgentBridgeTokens.self, from: data)
    }

    func save(_ tokens: AgentBridgeTokens) throws {
        delete()
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
