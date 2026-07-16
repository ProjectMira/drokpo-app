import Foundation

/// Something a member can share: a person's profile, a community page, a
/// community post, or a news story. Produces the hosted share link
/// (https://drokpo-backend.web.app/s/{type}/{id} — served by the backend's
/// public/share.html via a Hosting rewrite) and the message text dropped
/// into a chat when sharing in-app.
enum ShareableContent: Identifiable {
    case profile(FeedCard)
    case community(cid: String, name: String?)
    case post(CommunityPostCard)
    case news(NewsCard)

    /// Path segment mirrored by share.html, the /s/** Hosting rewrite, and
    /// ShareDestination.parse — keep all of them in sync.
    var pathType: String {
        switch self {
        case .profile(let card): card.isCommunity ? "community" : "user"
        case .community: "community"
        case .post: "post"
        case .news: "news"
        }
    }

    var contentId: String {
        switch self {
        case .profile(let card): card.uid
        case .community(let cid, _): cid
        case .post(let post): post.postId
        case .news(let news): news.newsId
        }
    }

    /// Caption used as the share-message headline and system-share subject.
    var title: String {
        switch self {
        case .profile(let card): card.displayName ?? "A Drokpo member"
        case .community(_, let name): name ?? "A community on Drokpo"
        case .post(let post): post.title ?? post.communityName ?? "A community post"
        case .news(let news): news.title ?? "A news story"
        }
    }

    var webURL: URL {
        AppConfig.apiBaseURL.appendingPathComponent("s/\(pathType)/\(contentId)")
    }

    /// What lands in the chat: a readable caption line above the link. The
    /// recipient's bubble renders this as a tappable shared-content card
    /// (SharedLinkMessage splits it back apart).
    var messageText: String { "\(title)\n\(webURL.absoluteString)" }

    var id: String { "\(pathType)-\(contentId)" }
}

/// A parsed incoming share link — from a chat-bubble tap, the drokpo://
/// scheme, or a universal link. MainTabView resolves and presents it.
enum ShareDestination: Identifiable, Equatable, Hashable {
    case user(String)
    case community(String)
    case post(String)
    case news(String)

    var id: String {
        switch self {
        case .user(let id): "user-\(id)"
        case .community(let id): "community-\(id)"
        case .post(let id): "post-\(id)"
        case .news(let id): "news-\(id)"
        }
    }

    static func make(type: String, id: String) -> ShareDestination? {
        guard !id.isEmpty else { return nil }
        switch type {
        case "user": return .user(id)
        case "community": return .community(id)
        case "post": return .post(id)
        case "news": return .news(id)
        default: return nil
        }
    }

    /// Accepts both link forms: https://drokpo-backend.web.app/s/{type}/{id}
    /// and drokpo://s/{type}/{id} (where "s" arrives as the URL host).
    static func parse(url: URL) -> ShareDestination? {
        let segments: [String]
        if url.scheme == "drokpo" {
            segments = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        } else if url.host == AppConfig.apiBaseURL.host {
            segments = url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        guard segments.count >= 3, segments[0] == "s" else { return nil }
        return make(type: segments[1], id: segments[2])
    }
}

/// A chat message that carries a share link: the parsed destination plus the
/// caption line(s) around it, for rendering as a tappable card instead of a
/// wall of URL.
struct SharedLinkMessage {
    let destination: ShareDestination
    let caption: String?

    init?(text: String) {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let linkLine = lines.first(where: { line in
            URL(string: line).flatMap(ShareDestination.parse) != nil
        }), let destination = URL(string: linkLine).flatMap(ShareDestination.parse) else {
            return nil
        }
        self.destination = destination
        let rest = lines.filter { $0 != linkLine && !$0.isEmpty }.joined(separator: "\n")
        caption = rest.isEmpty ? nil : rest
    }

    /// "Shared a profile" / "… community" / "… community post" / "… news story".
    var kindLabel: String {
        switch destination {
        case .user: "a profile"
        case .community: "a community"
        case .post: "a community post"
        case .news: "a news story"
        }
    }

    var icon: String {
        switch destination {
        case .user: "person.crop.circle"
        case .community: "person.3"
        case .post: "megaphone"
        case .news: "newspaper"
        }
    }
}
