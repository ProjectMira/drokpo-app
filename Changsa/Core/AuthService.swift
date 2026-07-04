import AuthenticationServices
import CryptoKit
import FirebaseAuth
import GoogleSignIn
import UIKit

enum AuthServiceError: LocalizedError {
    case missingToken
    case noPresenter

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Sign-in didn't return a valid token. Please try again."
        case .noPresenter: return "Couldn't present the sign-in screen."
        }
    }
}

enum AuthService {
    // MARK: Apple

    /// Raw nonce for the in-flight Apple sign-in request; Apple echoes its
    /// SHA-256 back in the identity token and Firebase verifies the pair.
    private static var currentNonce: String?

    static func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = sha256(nonce)
    }

    static func completeAppleSignIn(_ authorization: ASAuthorization) async throws {
        guard
            let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = appleCredential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else { throw AuthServiceError.missingToken }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        try await Auth.auth().signIn(with: credential)
    }

    // MARK: Google

    @MainActor
    static func signInWithGoogle() async throws {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = scene.keyWindow?.rootViewController
        else { throw AuthServiceError.noPresenter }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthServiceError.missingToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        try await Auth.auth().signIn(with: credential)
    }

    // MARK: Nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
