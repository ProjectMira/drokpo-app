import FirebaseAuth
import FirebaseMessaging
import UIKit
import UserNotifications

/// Keeps this device's FCM token registered with the backend
/// (POST/DELETE /api/profile/me/fcm-tokens) so the Cloud Functions can push
/// "new match" and "new message" notifications.
final class PushService: NSObject {
    static let shared = PushService()

    /// Latest token minted by FCM; may rotate at any time.
    private var currentToken: String?
    /// Token the backend currently has for this device.
    private var uploadedToken: String?

    /// Hook up delegates; call once at launch, after FirebaseApp.configure().
    func configure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for notification permission and sync the token. Called whenever an
    /// active account returns to the foreground; iOS only presents its prompt
    /// once, while a later Settings change is picked up automatically.
    func enable() {
        Task { @MainActor in
            guard Auth.auth().currentUser != nil else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted: Bool
            if settings.authorizationStatus == .notDetermined {
                granted = (try? await center.requestAuthorization(options: options)) ?? false
            } else {
                granted = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                    || settings.authorizationStatus == .ephemeral
            }
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
            fetchCurrentToken()
            self.uploadTokenIfNeeded()
        }
    }

    /// Detach this device from the profile; call before signing out, while the
    /// auth session is still valid.
    func unregister() async {
        guard let token = uploadedToken ?? currentToken else { return }
        let _: EmptyResponse? = try? await APIClient.shared.delete(
            "/api/profile/me/fcm-tokens",
            query: [URLQueryItem(name: "token", value: token)]
        )
        uploadedToken = nil
    }

    private func uploadTokenIfNeeded() {
        guard let token = currentToken, token != uploadedToken,
              Auth.auth().currentUser != nil else { return }
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/profile/me/fcm-tokens",
                    body: FcmTokenIn(token: token)
                )
                self.uploadedToken = token
            } catch {
                // Retried on the next enable() or token rotation.
            }
        }
    }

    /// The delegate callback normally supplies this token. Fetch it as well:
    /// Firebase can mint a token before an account finishes loading, in which
    /// case relying only on the callback left the device unregistered until a
    /// future token rotation.
    private func fetchCurrentToken() {
        Messaging.messaging().token { [weak self] token, _ in
            guard let self, let token else { return }
            self.currentToken = token
            self.uploadTokenIfNeeded()
        }
    }
}

extension PushService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        currentToken = fcmToken
        uploadTokenIfNeeded()
    }
}

extension PushService: UNUserNotificationCenterDelegate {
    // Show notifications as banners even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Notification tap (including cold-start — the delegate is set at launch).
    // FCM data payloads arrive as top-level keys in userInfo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String
        let matchId = userInfo["matchId"] as? String
        guard type != nil || matchId != nil else { return }
        await MainActor.run {
            DeepLinkRouter.shared.handle(type: type, matchId: matchId)
        }
    }
}
