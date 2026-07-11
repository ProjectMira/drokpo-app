import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable {
        case discover, likes, chats, profile
    }

    @Environment(SessionStore.self) private var session
    @State private var chats = ChatStore()
    @State private var router = DeepLinkRouter.shared
    @State private var selection: Tab = .discover

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("Discover", systemImage: "rectangle.stack.fill") }
                .tag(Tab.discover)
            LikesView()
                .tabItem { Label("Likes", systemImage: "heart.fill") }
                .tag(Tab.likes)
            ChatsView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(chats.totalUnread)
                .tag(Tab.chats)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(Tab.profile)
        }
        .environment(chats)
        .onAppear {
            if let uid = session.uid { chats.start(uid: uid) }
            routeDeepLink()
        }
        .onChange(of: router.pendingMatchId) { routeDeepLink() }
        .onChange(of: router.pendingType) { routeDeepLink() }
        .onDisappear { chats.stop() }
    }

    /// A "match"/"message" push-tap lands on the Chats tab; ChatsView consumes
    /// the router to decide whether to open the thread, so don't clear it
    /// here. A "like" push has no thread to open, so land on Likes and
    /// consume it immediately.
    private func routeDeepLink() {
        guard router.pendingMatchId != nil || router.pendingType != nil else { return }
        if router.pendingType == "like" {
            selection = .likes
            router.clear()
        } else {
            selection = .chats
        }
    }
}
