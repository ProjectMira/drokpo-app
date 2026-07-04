import Foundation

enum AppConfig {
    /// Backend base URL (Cloud Run deployment).
    static let apiBaseURL = URL(string: "https://changsa-api-cxxeyearxa-uc.a.run.app")!

    static var hasFirebaseConfig: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }
}
