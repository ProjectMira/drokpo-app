import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("Changsa")
                    .font(.largeTitle.bold())
                Text("Find your person in the Tibetan community")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    AuthService.prepareAppleRequest(request)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        signIn { try await AuthService.completeAppleSignIn(authorization) }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)

                Button {
                    signIn { try await AuthService.signInWithGoogle() }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)

                Text("You must be 18 or older to use Changsa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .disabled(isSigningIn)
        }
        .overlay {
            if isSigningIn { ProgressView() }
        }
        .alert("Sign-in failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func signIn(_ operation: @escaping () async throws -> Void) {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await operation()
                // SessionStore's auth listener takes over from here.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
