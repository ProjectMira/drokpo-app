import Foundation

// NOTE: The backend's OpenAPI spec declares empty response schemas, so every
// response field here is optional and decoded defensively. Verify against the
// live API and tighten as the contract firms up.

struct GeoLocation: Codable, Equatable {
    var lat: Double
    var lng: Double
}

struct Preferences: Codable, Equatable {
    var ageMin: Int = 18
    var ageMax: Int = 99
    var distanceKm: Int = 50
}

struct Photo: Codable, Equatable, Identifiable, Hashable {
    var storagePath: String
    var order: Int?
    var url: String?

    var id: String { storagePath }
}

struct Profile: Codable, Equatable, Identifiable {
    var uid: String?
    var displayName: String?
    var dob: String?
    var gender: String?
    var seekingGenders: [String]?
    var bio: String?
    var occupation: String?
    var education: String?
    var region: String?
    var languages: [String]?
    var photos: [Photo]?
    var preferences: Preferences?
    var onboardingComplete: Bool?

    var id: String { uid ?? "me" }

    var age: Int? {
        guard let dob, let date = Self.dobFormatter.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }

    static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

struct FeedCard: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String?
    var age: Int?
    var dob: String?
    var region: String?
    var bio: String?
    var occupation: String?
    var languages: [String]?
    var photos: [Photo]?
    var distanceKm: Double?

    var id: String { uid }

    var displayAge: Int? {
        if let age { return age }
        guard let dob, let date = Profile.dobFormatter.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }
}

struct Match: Codable, Equatable, Identifiable {
    var matchId: String?
    var otherUser: FeedCard?
    var createdAt: String?

    var id: String { matchId ?? otherUser?.uid ?? UUID().uuidString }
}

struct SwipeResult: Codable {
    var matched: Bool?
    var matchId: String?
    var match: Match?

    var isMatch: Bool { matched ?? (matchId != nil || match != nil) }
}

/// The spec doesn't say whether list endpoints return a bare array or a wrapper
/// object, so accept both shapes.
struct TolerantList<Element: Decodable>: Decodable {
    var items: [Element]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var collected: [Element] = []
            while !unkeyed.isAtEnd {
                collected.append(try unkeyed.decode(Element.self))
            }
            items = collected
            return
        }
        let keyed = try decoder.container(keyedBy: AnyKey.self)
        for key in keyed.allKeys {
            if let list = try? keyed.decode([Element].self, forKey: key) {
                items = list
                return
            }
        }
        items = []
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - Request bodies

struct OnboardingIn: Encodable {
    var displayName: String
    var dob: String
    var gender: String
    var seekingGenders: [String]
    var bio: String
    var region: String
    var languages: [String]
    var location: GeoLocation
    var preferences: Preferences
}

struct PhotoConfirm: Encodable {
    var storagePath: String
    var order: Int
}

struct ProfileUpdate: Encodable {
    var displayName: String?
    var bio: String?
    var occupation: String?
    var education: String?
    var region: String?
    var languages: [String]?
    var seekingGenders: [String]?
    var preferences: Preferences?
}

struct SwipeIn: Encodable {
    var action: SwipeAction
}

enum SwipeAction: String, Encodable {
    case like, pass, superlike
}

struct ReportIn: Encodable {
    var reportedUid: String
    var reason: String
    var note: String
}

// MARK: - Shared vocabulary

enum Vocabulary {
    static let genders = ["male", "female"]
    static let regions = [
        "U-Tsang", "Kham", "Amdo",
        "India", "Nepal", "Bhutan",
        "North America", "Europe", "Australia", "Other",
    ]
    static let languages = ["Tibetan", "English", "Hindi", "Nepali", "Mandarin", "French", "German", "Other"]
    static let reportReasons = ["Fake profile", "Inappropriate photos", "Harassment", "Spam", "Underage", "Other"]

    /// Rough fallback coordinates per region for users who decline location access.
    static let regionCoordinates: [String: GeoLocation] = [
        "U-Tsang": .init(lat: 29.65, lng: 91.1),
        "Kham": .init(lat: 30.05, lng: 97.17),
        "Amdo": .init(lat: 36.03, lng: 103.73),
        "India": .init(lat: 32.22, lng: 76.32),
        "Nepal": .init(lat: 27.72, lng: 85.32),
        "Bhutan": .init(lat: 27.47, lng: 89.64),
        "North America": .init(lat: 40.71, lng: -74.0),
        "Europe": .init(lat: 47.37, lng: 8.54),
        "Australia": .init(lat: -33.87, lng: 151.21),
        "Other": .init(lat: 0, lng: 0),
    ]
}
