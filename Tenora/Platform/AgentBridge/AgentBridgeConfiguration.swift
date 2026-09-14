import Foundation

struct AgentBridgeConfiguration: Equatable, Sendable {
    let bridgeURL: URL
    let oauthIssuer: URL
    let oauthClientID: String
    let redirectURI = "tenora://oauth/callback"
    let scopes = "openid profile offline_access tasks:read tasks:sync"

    static func load(bundle: Bundle = .main) -> AgentBridgeConfiguration? {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String,
                  !raw.isEmpty, !raw.contains("$(") else { return nil }
            return raw
        }
        guard let bridge = value("TENORA_BRIDGE_URL").flatMap(URL.init(string:)),
              let issuer = value("TENORA_OAUTH_ISSUER").flatMap(URL.init(string:)),
              let clientID = value("TENORA_OAUTH_CLIENT_ID") else { return nil }
        return AgentBridgeConfiguration(bridgeURL: bridge, oauthIssuer: issuer, oauthClientID: clientID)
    }
}
