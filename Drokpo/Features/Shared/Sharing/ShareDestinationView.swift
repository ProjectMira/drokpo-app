import SwiftUI

/// Presents content that arrived via a share link (chat bubble tap, drokpo://
/// scheme, universal link): fetches the target by id and renders the same
/// detail view the rest of the app uses. Presented as a sheet by MainTabView.
struct ShareDestinationView: View {
    let destination: ShareDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .community(let cid):
            CommunityPageView(cid: cid)
        case .user(let uid):
            SharedUserLoader(uid: uid)
        case .post(let postId):
            SharedPostLoader(postId: postId)
        case .news(let newsId):
            SharedNewsLoader(newsId: newsId)
        }
    }
}

/// Shown when a shared item can't be fetched — deleted account, unpublished
/// post, or a block relationship (the backend 404s all of these alike).
private struct SharedContentUnavailable: View {
    var body: some View {
        ContentUnavailableView(
            "Content unavailable",
            systemImage: "link",
            description: Text("It may have been removed, or isn't available to you.")
        )
    }
}

private struct SharedUserLoader: View {
    let uid: String
    @State private var card: FeedCard?
    @State private var failed = false

    var body: some View {
        Group {
            if let card {
                if card.isCommunity {
                    CommunityPageView(cid: card.uid)
                } else {
                    ProfileDetailView(card: card)
                }
            } else if failed {
                SharedContentUnavailable()
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                card = try await APIClient.shared.get("/api/users/\(uid)")
            } catch {
                failed = true
            }
        }
    }
}

private struct SharedPostLoader: View {
    let postId: String
    @State private var post: CommunityPostCard?
    @State private var failed = false

    var body: some View {
        Group {
            if let post {
                SharedPostView(post: post)
            } else if failed {
                SharedContentUnavailable()
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                post = try await APIClient.shared.get("/api/posts/\(postId)")
            } catch {
                failed = true
            }
        }
    }
}

/// A live community post reached through a share link — voting, RSVP,
/// comments, and the link CTA all work, same as the Discover detail sheet.
private struct SharedPostView: View {
    @State var post: CommunityPostCard
    @State private var showComments = false
    @State private var urlToOpen: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            CommunityPostContentView(
                post: post,
                onVote: post.kind == "poll" ? { optionId in Task { await vote(optionId) } } : nil,
                onRsvp: post.kind == "event" ? { going in Task { await rsvp(going) } } : nil,
                onOpenLink: post.url != nil ? { urlToOpen = post.url } : nil,
                onOpenComments: { showComments = true }
            )
            .padding()
        }
        .navigationTitle(post.communityName ?? "Community post")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareButton(content: .post(post))
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(post: post)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $urlToOpen) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func vote(_ optionId: String) async {
        do {
            let result: VoteResult = try await APIClient.shared.post(
                "/api/posts/\(post.postId)/vote", body: VoteIn(optionId: optionId)
            )
            post.poll = result.poll
            post.myVote = result.myVote
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rsvp(_ going: Bool) async {
        do {
            let result: RsvpResult = going
                ? try await APIClient.shared.post("/api/posts/\(post.postId)/rsvp")
                : try await APIClient.shared.delete("/api/posts/\(post.postId)/rsvp")
            post.attendeeCount = result.attendeeCount
            post.myRsvp = result.going
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SharedNewsLoader: View {
    let newsId: String
    @State private var item: NewsCard?
    @State private var failed = false
    @State private var urlToOpen: URL?

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    NewsDetailContent(item: item) {
                        guard let url = item.url else { return }
                        urlToOpen = url
                        Task {
                            let _: EmptyResponse? = try? await APIClient.shared.post(
                                "/api/news/\(item.newsId)/events", body: ContentEventIn(event: "click")
                            )
                        }
                    }
                }
                .navigationTitle("News")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareButton(content: .news(item))
                    }
                }
            } else if failed {
                SharedContentUnavailable()
            } else {
                ProgressView()
            }
        }
        .sheet(item: $urlToOpen) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .task {
            do {
                item = try await APIClient.shared.get("/api/news/\(newsId)")
            } catch {
                failed = true
            }
        }
    }
}
