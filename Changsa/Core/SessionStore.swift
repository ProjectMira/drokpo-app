import Foundation
import FirebaseAuth

@Observable
final class SessionStore {
    enum State: Equatable {
        case loading, signedOut, needsOnboarding, active, failed
    }

    var state: State = .loading
    var myProfile: Profile?
    var lastError: String?

    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        guard AppConfig.hasFirebaseConfig else {
            state = .signedOut
            return
        }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if user == nil {
                    self.myProfile = nil
                    self.state = .signedOut
                } else {
                    await self.refreshProfile()
                }
            }
        }
    }

    @MainActor
    func refreshProfile() async {
        do {
            let profile: Profile = try await APIClient.shared.get("/api/profile/me")
            myProfile = profile
            state = (profile.onboardingComplete ?? true) ? .active : .needsOnboarding
        } catch APIError.http(let status, _) where status == 404 {
            state = .needsOnboarding
        } catch {
            lastError = error.localizedDescription
            state = .failed
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
