import SwiftUI

/// Root tab shell for both account types. Person and community accounts now
/// share the same five tabs — Discover, Likes, Communities, Chats, Profile —
/// so a community can match/chat as itself; the difference is which tab shows
/// for `.communities` (a person has none — see below) and `.profile` (their
/// own community page vs. a person's dating profile).
struct MainTabView: View {
    enum Tab: Hashable {
        case discover, likes, communities, chats, profile
    }

    @Environment(SessionStore.self) private var session
    @State private var chats = ChatStore()
    @State private var router = DeepLinkRouter.shared
    @State private var selection: Tab = .discover
    /// A shared-content link being shown (chat-bubble tap, drokpo:// URL).
    @State private var sharedDestination: ShareDestination?

    private var isCommunity: Bool { session.state == .activeCommunity }
    private var myCid: String { session.myCommunity?.uid ?? session.uid ?? "" }

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("Discover", systemImage: "rectangle.stack.fill") }
                .tag(Tab.discover)
            LikesView()
                .tabItem { Label("Likes", systemImage: "heart.fill") }
                .tag(Tab.likes)
            // Persons browse communities from a button on the Discover deck
            // instead of a root tab — this tab exists only for a community
            // account's own page (create posts, see the Instagram-style grid).
            if isCommunity {
                NavigationStack {
                    CommunityPageView(cid: myCid, ownerMode: true)
                }
                .tabItem { Label("Communities", systemImage: "person.3.fill") }
                .tag(Tab.communities)
            }
            ChatsView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(chats.totalUnread)
                .tag(Tab.chats)
            Group {
                if isCommunity {
                    CommunityProfileEditorView()
                } else {
                    ProfileView()
                }
            }
            .tabItem { Label("Profile", systemImage: "person.fill") }
            .tag(Tab.profile)
        }
        .environment(chats)
        .onAppear {
            if let uid = session.uid { chats.start(uid: uid) }
            routeDeepLink()
            consumePendingShare()
        }
        .onChange(of: router.pendingMatchId) { routeDeepLink() }
        .onChange(of: router.pendingType) { routeDeepLink() }
        .onChange(of: router.pendingShare) { consumePendingShare() }
        .onDisappear { chats.stop() }
        .sheet(item: $sharedDestination) { destination in
            ShareDestinationView(destination: destination)
        }
    }

    /// A "match"/"message" push-tap lands on the Chats tab; ChatsView consumes
    /// the router to decide whether to open the thread, so don't clear it
    /// here. A "like" push has no thread to open, so land on Likes (flagging
    /// LikesView to open its "Liked you" segment) and consume it immediately.
    private func routeDeepLink() {
        guard router.pendingMatchId != nil || router.pendingType != nil else { return }
        if router.pendingType == "like" {
            selection = .likes
            router.focusLikedYou = true
            router.clear()
        } else {
            selection = .chats
        }
    }

    private func consumePendingShare() {
        guard let destination = router.pendingShare else { return }
        router.pendingShare = nil
        sharedDestination = destination
    }
}
