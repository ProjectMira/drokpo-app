import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct ChangsaApp: App {
    @State private var session: SessionStore

    init() {
        if AppConfig.hasFirebaseConfig {
            FirebaseApp.configure()
            if let clientID = FirebaseApp.app()?.options.clientID {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            }
        }
        _session = State(initialValue: SessionStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if !AppConfig.hasFirebaseConfig {
                SetupNoticeView()
            } else {
                switch session.state {
                case .loading:
                    ProgressView()
                case .signedOut:
                    SignInView()
                case .needsOnboarding:
                    OnboardingFlow()
                case .active:
                    MainTabView()
                case .failed:
                    VStack(spacing: 16) {
                        Text("Couldn't load your profile.")
                        if let message = session.lastError {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("Retry") {
                            Task { await session.refreshProfile() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Sign out") { session.signOut() }
                    }
                    .padding()
                }
            }
        }
        .animation(.default, value: session.state)
    }
}

/// Shown when GoogleService-Info.plist is missing so the app still runs before Firebase is set up.
struct SetupNoticeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Firebase not configured")
                .font(.headline)
            Text("Add GoogleService-Info.plist to Changsa/Resources and rebuild.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
