import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum AppleSignInNonce {
    static func make() throws -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = 32
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw AccountAuthenticationError.service("Tenora couldn't prepare secure sign-in. Please try again.")
            }
            for byte in bytes where remaining > 0 && byte < characters.count {
                result.append(characters[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    static func hashed(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func identityToken(from result: Result<ASAuthorization, Error>) throws -> String {
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            throw AccountAuthenticationError.cancelled
        case .failure:
            throw AccountAuthenticationError.invalidCredential
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw AccountAuthenticationError.invalidCredential
            }
            return token
        }
    }
}
