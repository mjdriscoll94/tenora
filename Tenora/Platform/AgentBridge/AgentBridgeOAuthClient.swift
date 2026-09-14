import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class AgentBridgeOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(configuration: AgentBridgeConfiguration) async throws -> AgentBridgeTokens {
        let metadata = try await metadata(for: configuration.oauthIssuer)
        let verifier = Self.randomURLSafeString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = UUID().uuidString
        var components = try urlComponents(metadata.authorizationEndpoint)
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: configuration.oauthClientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI), URLQueryItem(name: "scope", value: configuration.scopes),
            URLQueryItem(name: "state", value: state), URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "resource", value: configuration.bridgeURL.absoluteString)
        ]
        guard let authorizationURL = components.url else { throw BridgeOAuthError.invalidConfiguration }
        let callback = try await callbackURL(for: authorizationURL)
        guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw BridgeOAuthError.invalidCallback
        }
        let response = try await exchange(code: code, verifier: verifier, tokenEndpoint: metadata.tokenEndpoint, configuration: configuration)
        return response.tokens()
    }

    func refresh(configuration: AgentBridgeConfiguration, refreshToken: String) async throws -> AgentBridgeTokens {
        let metadata = try await metadata(for: configuration.oauthIssuer)
        var request = URLRequest(url: metadata.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: refreshToken),
                           URLQueryItem(name: "client_id", value: configuration.oauthClientID), URLQueryItem(name: "scope", value: configuration.scopes),
                           URLQueryItem(name: "resource", value: configuration.bridgeURL.absoluteString)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard (urlResponse as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeOAuthError.tokenExchangeFailed }
        return try JSONDecoder().decode(TokenResponse.self, from: data).tokens(fallbackRefreshToken: refreshToken)
    }

    private func callbackURL(for authorizationURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: "tenora") { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? BridgeOAuthError.cancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else { continuation.resume(throwing: BridgeOAuthError.cancelled); return }
        }
    }

    private func metadata(for issuer: URL) async throws -> OAuthMetadata {
        let url = issuer.appending(path: ".well-known/openid-configuration")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeOAuthError.invalidConfiguration }
        return try JSONDecoder().decode(OAuthMetadata.self, from: data)
    }

    private func exchange(code: String, verifier: String, tokenEndpoint: URL, configuration: AgentBridgeConfiguration) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "authorization_code"), URLQueryItem(name: "code", value: code),
                           URLQueryItem(name: "client_id", value: configuration.oauthClientID), URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
                           URLQueryItem(name: "code_verifier", value: verifier), URLQueryItem(name: "resource", value: configuration.bridgeURL.absoluteString)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeOAuthError.tokenExchangeFailed }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? UIWindow()
    }

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func urlComponents(_ url: URL) throws -> URLComponents {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw BridgeOAuthError.invalidConfiguration }
        return components
    }
}

private struct OAuthMetadata: Decodable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    enum CodingKeys: String, CodingKey { case authorizationEndpoint = "authorization_endpoint"; case tokenEndpoint = "token_endpoint" }
}
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token"; case expiresIn = "expires_in" }
    func tokens(fallbackRefreshToken: String? = nil) -> AgentBridgeTokens {
        AgentBridgeTokens(accessToken: accessToken, refreshToken: refreshToken ?? fallbackRefreshToken,
                          expiresAt: Date().addingTimeInterval(expiresIn ?? 3600))
    }
}
private enum BridgeOAuthError: LocalizedError {
    case invalidConfiguration, invalidCallback, tokenExchangeFailed, cancelled
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "The Agent Bridge login is not configured correctly."
        case .invalidCallback: "Tenora could not verify the login response."
        case .tokenExchangeFailed: "Tenora could not finish connecting your account."
        case .cancelled: "The Agent Bridge connection was cancelled."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
