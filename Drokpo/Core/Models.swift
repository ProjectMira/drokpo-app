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

/// Social handles. Instagram is the one handle every profile must have; the
/// backend rejects onboarding without it and never lets it be cleared.
struct Socials: Codable, Equatable {
    var instagram: String?
    var youtube: String?
    var tiktok: String?
    var facebook: String?
    var x: String?
    var wechat: String?
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
    var bio: String?
    var occupation: String?
    var education: String?
    var region: String?
    var languages: [String]?
    var interests: [String]?
    var answers: [String: String]?
    var socials: Socials?
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

    /// Your own profile shaped as the card other members see, for previewing.
    var asFeedCard: FeedCard {
        FeedCard(
            uid: uid ?? "me",
            displayName: displayName,
            age: age,
            dob: dob,
            region: region,
            bio: bio,
            occupation: occupation,
            education: education,
            languages: languages,
            interests: interests,
            answers: answers,
            socials: socials,
            photos: photos
        )
    }
}

struct FeedCard: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String?
    var age: Int?
    var dob: String?
    var region: String?
    var bio: String?
    var occupation: String?
    var education: String?
    var languages: [String]?
    var interests: [String]?
    var answers: [String: String]?
    var socials: Socials?
    var photos: [Photo]?
    var distanceKm: Double?

    var id: String { uid }

    var displayAge: Int? {
        if let age { return age }
        guard let dob, let date = Profile.dobFormatter.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }
}

/// A sponsored card served with the feed (see backend docs/ADS.md). Shown in
/// the Discover deck after every few real profiles; liking it opens `linkUrl`
/// in the in-app browser instead of recording a swipe.
struct AdCard: Codable, Equatable, Identifiable {
    var adId: String
    var title: String?
    var body: String?
    var linkUrl: String?
    var ctaLabel: String?
    var imageUrl: String?
    var photos: [Photo]?

    var id: String { adId }

    var url: URL? { linkUrl.flatMap(URL.init(string:)) }

    /// Creative to render — `photos` if present, else `imageUrl` wrapped as a
    /// single photo (the synthetic storagePath only serves as a cache key).
    var displayPhotos: [Photo] {
        if let photos, !photos.isEmpty { return photos }
        if let imageUrl { return [Photo(storagePath: "ad-image-\(adId)", order: 0, url: imageUrl)] }
        return []
    }
}

/// GET /api/feed response: real profiles plus every active content queue —
/// ads, news, and community posts — that the Discover deck interleaves in.
struct FeedResponse: Decodable {
    var candidates: [FeedCard]?
    var ads: [AdCard]?
    var news: [NewsCard]?
    var communityPosts: [CommunityPostCard]?
}

// MARK: - Typed feed items

/// Decodes to nil instead of sinking the whole array when one element is
/// malformed or has an unknown type (forward compatibility with future card
/// kinds the backend may start serving).
struct FailableItem<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// One entry in a server-ordered feed: `{"type": ..., "data": {...}}`.
enum FeedItem: Decodable, Identifiable {
    case person(FeedCard)
    case ad(AdCard)
    case news(NewsCard)
    case post(CommunityPostCard)

    var id: String {
        switch self {
        case .person(let card): "person-\(card.uid)"
        case .ad(let ad): "ad-\(ad.adId)"
        case .news(let item): "news-\(item.newsId)"
        case .post(let post): "post-\(post.postId)"
        }
    }

    private enum CodingKeys: String, CodingKey { case type, data }
    private struct UnknownTypeError: Error {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "person": self = .person(try container.decode(FeedCard.self, forKey: .data))
        case "ad": self = .ad(try container.decode(AdCard.self, forKey: .data))
        case "news": self = .news(try container.decode(NewsCard.self, forKey: .data))
        case "communityPost": self = .post(try container.decode(CommunityPostCard.self, forKey: .data))
        default: throw UnknownTypeError() // FailableItem maps this to nil
        }
    }
}

/// GET /api/feed decoded shape-agnostically: `items` when the server mixes
/// (?shape=items), or the legacy parallel arrays from an older backend —
/// FeedModel falls back to client-side mixing in that case.
struct FeedPage: Decodable {
    var items: [FeedItem]?
    var candidates: [FeedCard]?
    var ads: [AdCard]?
    var news: [NewsCard]?
    var communityPosts: [CommunityPostCard]?

    private enum CodingKeys: String, CodingKey { case items, candidates, ads, news, communityPosts }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try container.decodeIfPresent([FailableItem<FeedItem>].self, forKey: .items))?
            .compactMap(\.value)
        candidates = try container.decodeIfPresent([FeedCard].self, forKey: .candidates)
        ads = try container.decodeIfPresent([AdCard].self, forKey: .ads)
        news = try container.decodeIfPresent([NewsCard].self, forKey: .news)
        communityPosts = try container.decodeIfPresent([CommunityPostCard].self, forKey: .communityPosts)
    }
}

/// GET /api/communities/home — the joined-communities rail plus a typed feed
/// of their posts with sponsored cards interleaved.
struct CommunitiesHomeResponse: Decodable {
    var communities: [CommunityProfile]?
    var items: [FeedItem]?

    private enum CodingKeys: String, CodingKey { case communities, items }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        communities = try container.decodeIfPresent([CommunityProfile].self, forKey: .communities)
        items = (try container.decodeIfPresent([FailableItem<FeedItem>].self, forKey: .items))?
            .compactMap(\.value)
    }
}

/// One saved (liked) content card from GET /api/likes/content.
enum LikedContent: Decodable, Identifiable {
    case news(NewsCard, likedAt: String?)
    case post(CommunityPostCard, likedAt: String?)

    var id: String {
        switch self {
        case .news(let item, _): "liked-news-\(item.newsId)"
        case .post(let post, _): "liked-post-\(post.postId)"
        }
    }

    var likedAt: String? {
        switch self {
        case .news(_, let likedAt), .post(_, let likedAt): likedAt
        }
    }

    private enum CodingKeys: String, CodingKey { case type, likedAt, data }
    private struct UnknownTypeError: Error {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let likedAt = try container.decodeIfPresent(String.self, forKey: .likedAt)
        switch try container.decode(String.self, forKey: .type) {
        case "news": self = .news(try container.decode(NewsCard.self, forKey: .data), likedAt: likedAt)
        case "communityPost": self = .post(try container.decode(CommunityPostCard.self, forKey: .data), likedAt: likedAt)
        default: throw UnknownTypeError()
        }
    }
}

struct LikedContentResponse: Decodable {
    var items: [LikedContent]?

    private enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try container.decodeIfPresent([FailableItem<LikedContent>].self, forKey: .items))?
            .compactMap(\.value)
    }
}

// MARK: - Communities

struct ContactPerson: Codable, Equatable {
    var name: String?
    var role: String?
    var phone: String?
    var email: String?
}

struct CommunityAddress: Codable, Equatable {
    var line1: String?
    var city: String?
    var state: String?
    var country: String?
    var postalCode: String?
}

/// A community/organization account — the alternative to `Profile` for the
/// same Firebase Auth uid (see backend docs/COMMUNITIES.md). `joined` is only
/// populated on directory/detail responses, not on `GET /api/communities/me`.
struct CommunityProfile: Codable, Equatable, Identifiable {
    var uid: String?
    var name: String?
    var description: String?
    var website: String?
    var phone: String?
    var email: String?
    var contactPerson: ContactPerson?
    var address: CommunityAddress?
    var socials: Socials?
    var photos: [Photo]?
    var verification: String?
    var memberCount: Int?
    var joined: Bool?

    var id: String { uid ?? "community" }

    var isVerified: Bool { verification == "verified" }
    var isPending: Bool { verification == "pending" || verification == nil }
}

/// GET /api/account — the single call the app makes at launch to decide
/// which experience (and which onboarding, if any) to route into.
struct AccountResponse: Decodable {
    var accountType: String?
    var profile: Profile?
    var community: CommunityProfile?
}

struct CommunityOnboardingIn: Encodable {
    var name: String
    var description: String
    var website: String?
    var phone: String?
    var email: String?
    var contactPerson: ContactPerson
    var address: CommunityAddress
    var socials: Socials?
}

struct CommunityUpdate: Encodable {
    var name: String?
    var description: String?
    var website: String?
    var phone: String?
    var email: String?
    var contactPerson: ContactPerson?
    var address: CommunityAddress?
    var socials: Socials?
}

struct CommunityPhotoConfirm: Encodable {
    var storagePath: String
    var order: Int
}

struct CommunityPhotoOrderUpdate: Encodable {
    var storagePaths: [String]
}

/// One entry in a poll post: `id` is server-assigned and stable — never
/// re-derive it client-side (votes reference it).
struct PollOption: Codable, Equatable, Identifiable {
    var id: String
    var label: String
}

struct Poll: Codable, Equatable {
    var options: [PollOption]
    var counts: [String: Int]

    // Decode defensively like every other response model: a poll doc missing
    // counts/options (hand-edited in the console) must degrade to an empty
    // poll, not fail the decode of the entire posts page it rides in.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        options = (try? container.decodeIfPresent([PollOption].self, forKey: .options)) ?? []
        counts = (try? container.decodeIfPresent([String: Int].self, forKey: .counts)) ?? [:]
    }

    init(options: [PollOption], counts: [String: Int]) {
        self.options = options
        self.counts = counts
    }

    var totalVotes: Int { counts.values.reduce(0, +) }

    func percentage(for optionId: String) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(counts[optionId] ?? 0) / Double(totalVotes)
    }
}

/// A community's post, in one of four kinds — announcement, link, poll, or
/// event. Shown on a community's page and interleaved into the Discover deck.
struct CommunityPostCard: Codable, Equatable, Identifiable {
    var postId: String
    var communityId: String?
    var communityName: String?
    var communityLogoUrl: String?
    var kind: String? // "announcement" | "link" | "poll" | "event"
    var title: String?
    var body: String?
    var imageUrl: String?
    var linkUrl: String?
    var ctaLabel: String?
    var poll: Poll?
    /// Only meaningful to the owning community viewing its own posts list —
    /// everyone else's query only ever returns active == true posts anyway.
    var active: Bool?
    var myVote: String?
    /// ISO 8601 with a UTC offset — see `eventDate` for a parsed Date.
    var eventAt: String?
    var location: String?
    var attendeeCount: Int?
    var myRsvp: Bool?
    var createdAt: String?

    var id: String { postId }
    var url: URL? { linkUrl.flatMap(URL.init(string:)) }

    var eventDate: Date? {
        guard let eventAt else { return nil }
        return Self.isoFormatter.date(from: eventAt) ?? Self.isoFractionalFormatter.date(from: eventAt)
    }

    var displayPhotos: [Photo] {
        guard let imageUrl else { return [] }
        return [Photo(storagePath: "post-image-\(postId)", order: 0, url: imageUrl)]
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct CommunityPostIn: Encodable {
    var kind: String
    var title: String
    var body: String = ""
    var imageUrl: String?
    var photoStoragePath: String?
    var linkUrl: String?
    var ctaLabel: String?
    var pollOptions: [String]?
    var eventAt: String?
    var location: String?
}

struct CommunityPostUpdate: Encodable {
    var title: String?
    var body: String?
    var imageUrl: String?
    var linkUrl: String?
    var ctaLabel: String?
    var active: Bool?
}

struct VoteIn: Encodable {
    var optionId: String
}

/// POST /api/posts/{postId}/vote response.
struct VoteResult: Decodable {
    var poll: Poll?
    var myVote: String?
}

/// POST/DELETE /api/posts/{postId}/rsvp response.
struct RsvpResult: Decodable {
    var attendeeCount: Int?
    var going: Bool?
}

/// A summarized news card for the Discover feed (see backend docs/DATA_SCHEMA.md
/// `news/{newsId}`) — authored by the news-digest skill, never by the app.
struct NewsCard: Codable, Equatable, Identifiable {
    var newsId: String
    var title: String?
    var gist: String?
    var summary: String?
    var sourceUrl: String?
    var sourceName: String?
    var imageUrl: String?
    var publishedAt: String?

    var id: String { newsId }
    var url: URL? { sourceUrl.flatMap(URL.init(string:)) }

    var displayPhotos: [Photo] {
        guard let imageUrl else { return [] }
        return [Photo(storagePath: "news-image-\(newsId)", order: 0, url: imageUrl)]
    }

    /// `publishedAt` arrives as full ISO 8601 (with or without offset) or a
    /// bare date, depending on what the source article exposed.
    var publishedDate: Date? {
        guard let publishedAt else { return nil }
        if let date = ISO8601DateFormatter().date(from: publishedAt) { return date }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: publishedAt) { return date }
        }
        return nil
    }

    /// "2d ago"-style label for cards and the detail sheet; nil when the
    /// published date is missing or unparseable.
    var relativePublished: String? {
        guard let date = publishedDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// GET /api/communities, GET /api/communities/mine
struct CommunityListResponse: Decodable {
    var communities: [CommunityProfile]?
}

/// GET /api/communities/{cid}/posts, GET /api/communities/feed
struct CommunityPostsResponse: Decodable {
    var posts: [CommunityPostCard]?
}

/// A slim member profile — GET /api/communities/{cid}/members deliberately
/// never returns the full dating-card view (bio/socials/prompts stay out).
struct CommunityMember: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String?
    var photo: Photo?
    var region: String?

    var id: String { uid }
}

/// GET /api/communities/{cid}/members
struct CommunityMembersResponse: Decodable {
    var members: [CommunityMember]?
}

struct LastMessage: Codable, Equatable {
    var text: String?
    var senderId: String?
}

struct Match: Codable, Equatable, Identifiable {
    var matchId: String?
    var users: [String]?
    var status: String?
    var otherUser: FeedCard?
    var lastMessage: LastMessage?
    var unreadCount: [String: Int]?
    var createdAt: String?

    var id: String { matchId ?? otherUser?.uid ?? UUID().uuidString }

    func unread(for uid: String?) -> Int {
        guard let uid else { return 0 }
        return unreadCount?[uid] ?? 0
    }
}

/// One entry from GET /api/swipes or GET /api/swipes/received.
struct SwipeEntry: Codable, Equatable, Identifiable {
    var uid: String?
    var action: String?
    var createdAt: String?
    var otherUser: FeedCard?
    var matchId: String?
    var matchStatus: String?

    var id: String { uid ?? otherUser?.uid ?? UUID().uuidString }
    var isMatched: Bool { matchId != nil }
}

struct SwipeResult: Codable {
    var matched: Bool?
    var matchId: String?
    var match: Match?

    var isMatch: Bool { matched ?? (matchId != nil || match != nil) }
}

/// One entry from GET /api/messages/sent.
struct SentMessage: Codable, Equatable, Identifiable {
    var messageId: String?
    var matchId: String?
    var senderId: String?
    var text: String?
    var createdAt: String?

    var id: String { messageId ?? UUID().uuidString }

    var sentDate: Date? {
        guard let createdAt else { return nil }
        return Self.isoFormatter.date(from: createdAt) ?? Self.isoFractionalFormatter.date(from: createdAt)
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
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
    var gender: String?
    var bio: String
    var occupation: String
    var education: String
    var region: String
    var languages: [String]
    var interests: [String]
    var answers: [String: String]
    var socials: Socials
    var location: GeoLocation
    var preferences: Preferences
}

struct PhotoConfirm: Encodable {
    var storagePath: String
    var order: Int
}

struct PhotoOrderUpdate: Encodable {
    var storagePaths: [String]
}

struct ProfileUpdate: Encodable {
    var displayName: String?
    var bio: String?
    var dob: String?
    var gender: String?
    var occupation: String?
    var education: String?
    var region: String?
    var languages: [String]?
    var interests: [String]?
    var answers: [String: String]?
    var socials: Socials?
    var location: GeoLocation?
    var preferences: Preferences?
}

struct SwipeIn: Encodable {
    var action: SwipeAction
}

enum SwipeAction: String, Encodable {
    case like, pass, superlike
}

struct MessageIn: Encodable {
    var text: String
}

struct FcmTokenIn: Encodable {
    var token: String
}

struct ReportIn: Encodable {
    var reportedUid: String
    var reason: String
    var note: String
}

/// POST /api/{ads,news,posts}/{id}/events — fire-and-forget content analytics,
/// same shape for all three content-card types the Discover deck shows.
struct ContentEventIn: Encodable {
    var event: String // "impression" | "click"
}

// MARK: - Profile questions

/// A profile prompt shown during onboarding/editing and rendered on the
/// profile detail card. `key` is the stable id stored in the profile's
/// `answers` map — never change a key once shipped.
struct ProfileQuestion: Identifiable {
    enum Kind {
        case choice([String])
        case text(placeholder: String)
    }

    let key: String
    let label: String
    let kind: Kind

    var id: String { key }
}

// MARK: - Shared vocabulary

enum Vocabulary {
    static let genders = ["male", "female"]
    static let regions = [
        "India", "Nepal", "Bhutan",
        "North America", "Europe", "Australia", "Other",
    ]
    static let languages = ["Tibetan", "English", "Hindi", "Nepali", "Mandarin", "French", "German", "Other"]
    static let interests = [
        "Momo cooking", "Gorshey", "Hiking", "Music", "Photography",
        "Reading", "Meditation", "Thangka painting", "Basketball", "Soccer",
        "Movies", "Travel", "Board games", "Volunteering",
        "Cooking", "Dancing", "Singing", "Art & design", "Gaming",
        "Cricket", "Chess", "Fitness", "Buddhism & philosophy", "Language exchange",
    ]
    static let educationLevels = [
        "High school", "Some college", "Bachelor's", "Master's", "PhD",
        "Monastic education", "Other",
    ]
    /// Friendship-flavoured prompts; all optional. Answers live in the
    /// profile's `answers` map keyed by `ProfileQuestion.key`.
    static let questions: [ProfileQuestion] = [
        .init(key: "lookingFor", label: "I'm here for", kind: .choice([
            "New friends", "Dating", "Friends first, then who knows", "Community & events",
        ])),
        .init(key: "teaChoice", label: "Chai or butter tea?", kind: .choice([
            "Chai", "Butter tea", "Both, please", "Coffee person",
        ])),
        .init(key: "travelledTo", label: "Places I've travelled to", kind: .text(
            placeholder: "Dharamshala, Kathmandu, New York…"
        )),
        .init(key: "favoriteMovies", label: "Movies I can rewatch forever", kind: .text(
            placeholder: "Your comfort films"
        )),
        .init(key: "favoriteMusic", label: "Songs on repeat", kind: .text(
            placeholder: "Artists or songs you love right now"
        )),
        .init(key: "perfectWeekend", label: "My perfect weekend", kind: .text(
            placeholder: "Hiking? Momo party? Netflix?"
        )),
    ]
    static let reportReasons = ["Fake profile", "Inappropriate photos", "Harassment", "Spam", "Underage", "Other"]

    /// Rough fallback coordinates per region for users who decline location access.
    static let regionCoordinates: [String: GeoLocation] = [
        "India": .init(lat: 32.22, lng: 76.32),
        "Nepal": .init(lat: 27.72, lng: 85.32),
        "Bhutan": .init(lat: 27.47, lng: 89.64),
        "North America": .init(lat: 40.71, lng: -74.0),
        "Europe": .init(lat: 47.37, lng: 8.54),
        "Australia": .init(lat: -33.87, lng: 151.21),
        "Other": .init(lat: 0, lng: 0),
    ]
}
