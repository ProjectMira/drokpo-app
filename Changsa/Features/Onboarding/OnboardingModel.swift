import CoreLocation
import SwiftUI

@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case basics, seeking, details, location, photos
    }

    var step: Step = .basics

    // Basics
    var displayName = ""
    var dob = Calendar.current.date(byAdding: .year, value: -25, to: .now)!
    var gender = ""

    // Seeking
    var seekingGenders: Set<String> = []
    var acceptedTerms = false

    // Details
    var region = ""
    var languages: Set<String> = []
    var bio = ""

    // Location
    var location: GeoLocation?

    // Photos
    var pickedImages: [UIImage] = []

    var isSubmitting = false
    var errorMessage: String?
    /// True once POST /api/onboarding/complete succeeds; the view uses this to
    /// hand control back to SessionStore.
    var completed = false

    var latestAllowedDOB: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: .now)!
    }

    var canAdvance: Bool {
        switch step {
        case .basics:
            return !displayName.trimmingCharacters(in: .whitespaces).isEmpty && !gender.isEmpty
        case .seeking:
            return !seekingGenders.isEmpty && acceptedTerms
        case .details:
            return !region.isEmpty && !languages.isEmpty
        case .location:
            return true // falls back to region coordinates
        case .photos:
            return !pickedImages.isEmpty
        }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    /// Advances to the next step; leaving the location step creates the profile
    /// on the backend so the photo confirm endpoint has something to attach to.
    @MainActor
    func advance() async {
        guard canAdvance else { return }
        switch step {
        case .location:
            await createProfile()
        case .photos:
            await uploadPhotosAndComplete()
        default:
            step = Step(rawValue: step.rawValue + 1) ?? step
        }
    }

    @MainActor
    private func createProfile() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let body = OnboardingIn(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            dob: Profile.dobFormatter.string(from: dob),
            gender: gender,
            seekingGenders: Array(seekingGenders),
            bio: bio,
            region: region,
            languages: Array(languages),
            location: location ?? Vocabulary.regionCoordinates[region] ?? GeoLocation(lat: 0, lng: 0),
            preferences: Preferences()
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/onboarding", body: body)
            step = .photos
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uploadPhotosAndComplete() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            for (index, image) in pickedImages.enumerated() {
                let storagePath = try await PhotoUploader.upload(image)
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/onboarding/photos/confirm",
                    body: PhotoConfirm(storagePath: storagePath, order: index)
                )
            }
            let _: EmptyResponse = try await APIClient.shared.post("/api/onboarding/complete")
            completed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - One-shot location

final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GeoLocation?, Never>?

    func requestLocation() async -> GeoLocation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                resume(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(with: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate
        resume(with: coordinate.map { GeoLocation(lat: $0.latitude, lng: $0.longitude) })
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(with: nil)
    }

    private func resume(with location: GeoLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}
