import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

/// Bridges UIKit app callbacks: hooks up push-notification delegates and
/// hands the APNs token to FCM.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if AppConfig.hasFirebaseConfig {
            PushService.shared.configure()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct DrokpoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("drokpo.appearance") private var appearance: AppearanceMode = .system
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
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    // Shared-content links (drokpo://s/... from share.html's
                    // "Open in Drokpo", or a hosted /s/... universal link)
                    // route to MainTabView via the DeepLinkRouter.
                    if let destination = ShareDestination.parse(url: url) {
                        DeepLinkRouter.shared.pendingShare = destination
                        return
                    }
                    // Phone-auth's reCAPTCHA fallback and Google sign-in share
                    // the same URL scheme (GOOGLE_REVERSED_CLIENT_ID) — give
                    // Firebase Auth first refusal so its verification flow
                    // isn't swallowed by GIDSignIn.
                    if Auth.auth().canHandle(url) { return }
                    GIDSignIn.sharedInstance.handle(url)
                }
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
                case .choosingAccountType:
                    AccountTypeChoiceView()
                case .needsOnboarding:
                    OnboardingFlow()
                case .activePerson:
                    MainTabView()
                case .needsCommunityOnboarding:
                    CommunityOnboardingFlow()
                case .activeCommunity:
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
            Text("Add GoogleService-Info.plist to Drokpo/Resources and rebuild.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
