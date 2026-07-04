import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Discover", systemImage: "rectangle.stack.fill") }
            MatchesView()
                .tabItem { Label("Matches", systemImage: "heart.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}
