import SwiftUI

struct LikesView: View {
    /// "You liked" sits left and is the default; "Liked you" moved right.
    private enum Direction: String, CaseIterable, Identifiable {
        case given = "You liked"
        case received = "Liked you"

        var id: String { rawValue }
    }

    /// Pill filters for "You liked": everything you saved, ordered newest
    /// first, or narrowed to people, community posts, or news stories.
    private enum GivenFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case friends = "Friends"
        case communities = "Communities"
        case news = "News"

        var id: String { rawValue }
    }

    /// One row of the merged "You liked" list.
    private enum GivenEntry: Identifiable {
        case person(SwipeEntry)
        case content(LikedContent)

        var id: String {
            switch self {
            case .person(let entry): "person-\(entry.id)"
            case .content(let content): content.id
            }
        }

        /// ISO timestamps sort correctly as strings; missing ones sink to the bottom.
        var sortKey: String {
            switch self {
            case .person(let entry): entry.createdAt ?? ""
            case .content(let content): content.likedAt ?? ""
            }
        }
    }

    @State private var direction: Direction = .given
    @State private var givenFilter: GivenFilter = .all
    @State private var router = DeepLinkRouter.shared
    @State private var received: [SwipeEntry] = []
    @State private var given: [SwipeEntry] = []
    @State private var likedContent: [LikedContent] = []
    @State private var isLoading = true
    @State private var matched: (name: String, matchId: String?)?
    @State private var errorMessage: String?
    @State private var urlToOpen: URL?

    private var givenEntries: [GivenEntry] {
        var entries: [GivenEntry] = []
        if givenFilter == .all || givenFilter == .friends {
            entries += given.map(GivenEntry.person)
        }
        if givenFilter == .all || givenFilter == .communities {
            entries += likedContent.compactMap { if case .post = $0 { .content($0) } else { nil } }
        }
        if givenFilter == .all || givenFilter == .news {
            entries += likedContent.compactMap { if case .news = $0 { .content($0) } else { nil } }
        }
        return entries.sorted { $0.sortKey > $1.sortKey }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Direction", selection: $direction) {
                    ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if direction == .given {
                    filterPills
                }

                Group {
                    if isLoading {
                        ProgressView().frame(maxHeight: .infinity)
                    } else if direction == .received {
                        if received.isEmpty { emptyState } else { receivedList }
                    } else {
                        if givenEntries.isEmpty { emptyState } else { givenList }
                    }
                }
            }
            .navigationTitle("Likes")
            .onAppear {
                consumeLikePush()
                Task { await load() }
            }
            .onChange(of: router.focusLikedYou) { consumeLikePush() }
            .refreshable { await load() }
            .sheet(item: $urlToOpen) { url in
                SafariView(url: url)
            }
            .alert("It's a match!", isPresented: .init(
                get: { matched != nil },
                set: { if !$0 { matched = nil } }
            )) {
                Button("Say hi") {
                    if let matchId = matched?.matchId {
                        DeepLinkRouter.shared.handle(type: "message", matchId: matchId)
                    }
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text("You and \(matched?.name ?? "they") liked each other.")
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
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GivenFilter.allCases) { filter in
                    Button {
                        givenFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(givenFilter == filter ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(givenFilter == filter ? Color.accentColor.opacity(0.18) : Color(.systemGray6))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private var receivedList: some View {
        List(received) { entry in
            if let card = entry.otherUser {
                NavigationLink {
                    if card.isCommunity {
                        CommunityPageView(cid: card.uid)
                    } else {
                        ProfileDetailView(
                            card: card,
                            context: .likedYou(onLikeBack: { await likeBack(card) })
                        )
                    }
                } label: {
                    LikeRow(card: card, showLikeBack: true) {
                        Task { await likeBackFromRow(card) }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var givenList: some View {
        List {
            ForEach(givenEntries) { entry in
                givenRow(entry)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func givenRow(_ entry: GivenEntry) -> some View {
        switch entry {
        case .person(let swipe):
            if let card = swipe.otherUser {
                NavigationLink {
                    if card.isCommunity {
                        CommunityPageView(cid: card.uid)
                    } else {
                        ProfileDetailView(card: card)
                    }
                } label: {
                    LikeRow(card: card, showLikeBack: false) {}
                }
            }
        case .content(.news(let item, _)):
            LikedNewsRow(item: item) {
                if let url = item.url {
                    urlToOpen = url
                    reportClick(path: "news/\(item.newsId)")
                }
            }
            .swipeActions {
                Button("Remove", role: .destructive) {
                    Task { await unlikeNews(item) }
                }
            }
        case .content(.post(let post, _)):
            NavigationLink {
                LikedPostDetailView(post: post) {
                    if let url = post.url {
                        urlToOpen = url
                        reportClick(path: "posts/\(post.postId)")
                    }
                }
            } label: {
                LikedPostRow(post: post)
            }
            .swipeActions {
                Button("Remove", role: .destructive) {
                    Task { await unlikePost(post) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: direction == .received ? "heart" : "paperplane")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(direction == .received ? "No likes yet" : "Nothing saved yet")
                .font(.headline)
            Text(direction == .received
                 ? "Likes you receive will show up here."
                 : "People, news, and community posts you like in Discover will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }

    /// A "like" push should land on the "Liked you" segment (the default is
    /// "You liked") — MainTabView flags it on the router, consumed here.
    private func consumeLikePush() {
        guard router.focusLikedYou else { return }
        router.focusLikedYou = false
        direction = .received
    }

    /// Only shows the full-screen spinner on the very first load; later calls
    /// (tab reselected, pull-to-refresh, returning from a like push) refresh
    /// silently so the existing list doesn't flash.
    ///
    /// Matched people are dropped from both lists — they already show up in
    /// Chats (New matches / conversations), so keeping them here duplicated
    /// the same person under both "Liked you" and "You liked".
    private func load() async {
        if received.isEmpty && given.isEmpty && likedContent.isEmpty { isLoading = true }
        do {
            async let receivedList: TolerantList<SwipeEntry> = APIClient.shared.get(
                "/api/swipes/received", query: [URLQueryItem(name: "action", value: "like")]
            )
            async let givenList: TolerantList<SwipeEntry> = APIClient.shared.get(
                "/api/swipes", query: [URLQueryItem(name: "action", value: "like")]
            )
            async let contentList: LikedContentResponse = APIClient.shared.get("/api/likes/content")
            received = try await receivedList.items.filter { !$0.isMatched }
            given = try await givenList.items.filter { !$0.isMatched }
            likedContent = (try await contentList.items) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func reportClick(path: String) {
        Task {
            let _: EmptyResponse? = try? await APIClient.shared.post(
                "/api/\(path)/events", body: ContentEventIn(event: "click")
            )
        }
    }

    private func unlikeNews(_ item: NewsCard) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("/api/news/\(item.newsId)/like")
            likedContent.removeAll { $0.id == "liked-news-\(item.newsId)" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unlikePost(_ post: CommunityPostCard) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("/api/posts/\(post.postId)/like")
            likedContent.removeAll { $0.id == "liked-post-\(post.postId)" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Shared by both the row's quick-like heart and the pushed
    /// ProfileDetailView's "Like back" button. Only removes the row from
    /// `received` — it does NOT set `matched`, because ProfileDetailView
    /// shows its own match alert and setting `matched` here too would
    /// present two alerts for the same tap.
    @discardableResult
    private func likeBack(_ card: FeedCard) async -> SwipeResult? {
        do {
            let result: SwipeResult = try await APIClient.shared.post(
                "/api/swipes/\(card.uid)", body: SwipeIn(action: .like)
            )
            received.removeAll { $0.otherUser?.uid == card.uid }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func likeBackFromRow(_ card: FeedCard) async {
        guard let result = await likeBack(card), result.isMatch else { return }
        matched = (name: card.displayName ?? "they", matchId: result.matchId ?? result.match?.matchId)
    }
}

/// A saved news story in the "You liked" list.
private struct LikedNewsRow: View {
    let item: NewsCard
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                RemotePhotoView(photo: item.displayPhotos.first)
                    .frame(width: 72, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    if let sourceName = item.sourceName {
                        Text(sourceName.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title ?? "—")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A saved community post in the "You liked" list.
private struct LikedPostRow: View {
    let post: CommunityPostCard

    private var icon: String {
        switch post.kind {
        case "link": "link"
        case "poll": "chart.bar.fill"
        case "event": "calendar"
        default: "megaphone.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                if let name = post.communityName {
                    Text(name.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Text(post.title ?? "—")
                    .font(.subheadline.bold())
                    .lineLimit(2)
            }
        }
    }
}

/// Read-only detail for a saved community post. The snapshot may outlive the
/// live post (the community can unpublish it), so voting/RSVP aren't offered
/// here — just the content and its link.
private struct LikedPostDetailView: View {
    let post: CommunityPostCard
    let onOpenLink: () -> Void

    @State private var showComments = false

    var body: some View {
        ScrollView {
            CommunityPostContentView(
                post: post,
                onVote: nil,
                onRsvp: nil,
                onOpenLink: post.url != nil ? onOpenLink : nil,
                onOpenComments: { showComments = true }
            )
            .padding()
        }
        .navigationTitle(post.communityName ?? "Saved post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareButton(content: .post(post))
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(post: post)
                .presentationDetents([.medium, .large])
        }
    }
}

/// A single Likes-list row. Pulled out of `LikesView.likeList` into its own
/// view — nesting this much conditional content directly inside a `List`
/// row closure made the type checker choke on `List(entries) { ... }`
/// itself (a bogus "cannot convert to Binding<Data>" error unrelated to the
/// real content); a dedicated view type keeps each closure's body small
/// enough to type-check.
private struct LikeRow: View {
    let card: FeedCard
    let showLikeBack: Bool
    let onLikeBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemotePhotoView(photo: card.photos?.first)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.displayName ?? "—").font(.headline)
                    if let age = card.displayAge {
                        Text("\(age)").foregroundStyle(.secondary)
                    }
                }
                if card.isCommunity {
                    Text("Community")
                        .font(.caption2.bold())
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                } else if let region = card.region {
                    Text(region)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showLikeBack {
                Button(action: onLikeBack) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.brandRed)
                        .padding(8)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
