import SwiftUI

/// One Instagram-profile-style page for a community: header (logo, name,
/// verified seal, member count, description, website, Join for visiting
/// persons) above a 3-column grid of its posts. The owning community sees the
/// same page in `ownerMode` — a "New post" affordance, its own unpublished
/// posts (badged, dimmed), and a publish/unpublish toggle in the tapped-post
/// sheet. This is the single community page: it replaces the old
/// CommunityDetailView (visitor) and the CommunityPostsView list (owner).
struct CommunityPageView: View {
    let cid: String
    /// Directory/rail card data, shown immediately while the fuller detail
    /// fetch is in flight — avoids a blank header on push. Ignored in owner
    /// mode (the header reads live from the session instead).
    var preview: CommunityProfile?
    var ownerMode = false

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var visitorCommunity: CommunityProfile?
    @State private var showReportReasons = false
    @State private var showBlockConfirm = false
    @State private var posts: [CommunityPostCard] = []
    @State private var isLoadingHeader = true
    @State private var isLoadingPosts = true
    @State private var isLoadingMore = false
    @State private var hasMorePosts = true
    @State private var isJoining = false
    @State private var showComposer = false
    @State private var selectedPost: CommunityPostCard?
    @State private var errorMessage: String?
    @State private var urlToOpen: URL?
    @State private var pendingURL: URL?

    /// Bumped on every join/leave; a load() started before the bump must not
    /// overwrite joined/memberCount with its pre-toggle snapshot.
    @State private var joinGeneration = 0

    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(cid: String, preview: CommunityProfile? = nil, ownerMode: Bool = false) {
        self.cid = cid
        self.preview = preview
        self.ownerMode = ownerMode
        _visitorCommunity = State(initialValue: preview)
    }

    /// The community whose header/verification this page reflects — the
    /// session's live copy in owner mode (GET /communities/{cid} 404s for an
    /// unverified community, since it isn't publicly listed yet), the fetched
    /// visitor snapshot otherwise.
    private var community: CommunityProfile? {
        ownerMode ? session.myCommunity : visitorCommunity
    }

    private var isVerified: Bool { community?.isVerified ?? false }

    var body: some View {
        pageBody
            .sheet(isPresented: $showComposer) {
                CommunityPostComposerView {
                    await load()
                }
            }
            .sheet(item: $selectedPost, onDismiss: presentPendingURL) { post in
                postDetailSheet(post)
            }
            .sheet(item: $urlToOpen) { url in
                SafariView(url: url)
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

    private var pageBody: some View {
        ScrollView {
            pageContent
        }
        .navigationTitle(community?.name ?? "Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareButton(content: .community(cid: cid, name: community?.name))
            }
            if ownerMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report", role: .destructive) { showReportReasons = true }
                        Button("Block", role: .destructive) { showBlockConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Report or block")
                }
            }
        }
        .confirmationDialog(
            "Why are you reporting this community?",
            isPresented: $showReportReasons,
            titleVisibility: .visible
        ) {
            ForEach(Vocabulary.reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) { Task { await report(reason: reason) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Block \(community?.name ?? "this community")?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { Task { await block() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see this community or its posts.")
        }
        .overlay { if isLoadingHeader && community == nil { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func postDetailSheet(_ post: CommunityPostCard) -> some View {
        CommunityPostDetailSheet(
            post: post,
            ownerMode: ownerMode,
            onVote: post.kind == "poll" ? { optionId in Task { await vote(post, optionId: optionId) } } : nil,
            onRsvp: post.kind == "event" ? { going in Task { await rsvp(post, going: going) } } : nil,
            onOpenLink: post.url != nil ? { pendingURL = post.url; selectedPost = nil } : nil,
            onTogglePublish: ownerMode ? { Task { await toggleActive(post) } } : nil
        )
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.bottom, 14)
            if ownerMode && !isVerified {
                PendingVerificationBanner()
                    .padding(.bottom, 10)
            }
            grid
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                RemotePhotoView(photo: community?.photos?.first)
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(community?.name ?? "Community")
                            .font(.title3.bold())
                        if community?.isVerified == true {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                        }
                    }
                    memberCountRow
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            if let description = community?.description, !description.isEmpty {
                Text(description).font(.subheadline)
            }

            HStack(spacing: 12) {
                actionButton
                if let website = community?.website, let url = URL(string: website) {
                    Button {
                        urlToOpen = url
                    } label: {
                        Label("Website", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// A count-only label for non-members (member lists are members-only —
    /// see docs/COMMUNITIES.md), or a link into the member list for the owner
    /// or a joined visitor.
    @ViewBuilder
    private var memberCountRow: some View {
        let count = community?.memberCount ?? 0
        let label = Text("\(count) member\(count == 1 ? "" : "s")")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if ownerMode || visitorCommunity?.joined == true {
            NavigationLink { CommunityMembersView(cid: cid) } label: { label }
        } else {
            label
        }
    }

    /// Owner sees "New post"; a visiting person sees Join/Joined; a visiting
    /// community account sees neither — communities don't join communities.
    @ViewBuilder
    private var actionButton: some View {
        if ownerMode {
            Button {
                showComposer = true
            } label: {
                Label("New post", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        } else if session.state != .activeCommunity {
            joinButton
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        let label = Group {
            if isJoining {
                ProgressView()
            } else {
                Text(visitorCommunity?.joined == true ? "Joined" : "Join")
            }
        }
        if visitorCommunity?.joined == true {
            Button { Task { await toggleJoin() } } label: { label }
                .buttonStyle(.bordered)
                .disabled(isJoining)
        } else {
            Button { Task { await toggleJoin() } } label: { label }
                .buttonStyle(.borderedProminent)
                .disabled(isJoining)
        }
    }

    // MARK: Grid

    @ViewBuilder
    private var grid: some View {
        if posts.isEmpty && !isLoadingPosts {
            ContentUnavailableView(
                "No posts yet",
                systemImage: "square.grid.3x3",
                description: Text(emptyGridMessage)
            )
            .padding(.top, 40)
        } else {
            LazyVGrid(columns: Self.gridColumns, spacing: 2) {
                ForEach(posts) { post in
                    Button {
                        selectedPost = post
                    } label: {
                        PostTile(post: post, showUnpublishedBadge: ownerMode)
                    }
                    .buttonStyle(.plain)
                    .onAppear { loadMoreIfNeeded(currentPost: post) }
                }
            }
            if isLoadingMore {
                ProgressView().padding()
            }
        }
    }

    private var emptyGridMessage: String {
        ownerMode ? "Share an announcement, link, poll, or event." : "Check back soon."
    }

    // MARK: Data

    private func load() async {
        isLoadingPosts = true
        hasMorePosts = true
        // Owner mode never fetches a header (it reads session.myCommunity,
        // always already populated by the time this view exists) — resolve
        // isLoadingHeader immediately so its loading overlay can't get stuck.
        if ownerMode { isLoadingHeader = false }
        defer { isLoadingPosts = false }
        do {
            if !ownerMode {
                isLoadingHeader = true
                let generationAtFetch = joinGeneration
                var result: CommunityProfile = try await APIClient.shared.get("/api/communities/\(cid)")
                if generationAtFetch != joinGeneration {
                    // A join/leave landed while this GET was in flight — keep
                    // the locally-updated membership state, take everything else.
                    result.joined = visitorCommunity?.joined
                    result.memberCount = visitorCommunity?.memberCount
                }
                visitorCommunity = result
                isLoadingHeader = false
            }
            let response: CommunityPostsResponse = try await APIClient.shared.get(
                "/api/communities/\(cid)/posts", query: [URLQueryItem(name: "limit", value: "30")]
            )
            posts = response.posts ?? []
            hasMorePosts = !posts.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(currentPost: CommunityPostCard) {
        guard hasMorePosts, !isLoadingMore, currentPost.id == posts.last?.id else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard let lastId = posts.last?.postId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response: CommunityPostsResponse = try await APIClient.shared.get(
                "/api/communities/\(cid)/posts",
                query: [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "before", value: lastId)]
            )
            let newPosts = response.posts ?? []
            hasMorePosts = !newPosts.isEmpty
            posts.append(contentsOf: newPosts)
        } catch {
            // Silent — a pagination hiccup shouldn't interrupt browsing.
        }
    }

    private func presentPendingURL() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        urlToOpen = url
    }

    private func report(reason: String) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                "/api/reports",
                body: ReportIn(reportedUid: cid, reason: reason, note: "")
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func block() async {
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(cid)")
            BlockStore.shared.record(uid: cid, displayName: community?.name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleJoin() async {
        isJoining = true
        defer { isJoining = false }
        let wasJoined = visitorCommunity?.joined == true
        do {
            if wasJoined {
                let _: EmptyResponse = try await APIClient.shared.delete("/api/communities/\(cid)/join")
                visitorCommunity?.joined = false
                visitorCommunity?.memberCount = max(0, (visitorCommunity?.memberCount ?? 1) - 1)
            } else {
                let _: EmptyResponse = try await APIClient.shared.post("/api/communities/\(cid)/join")
                visitorCommunity?.joined = true
                visitorCommunity?.memberCount = (visitorCommunity?.memberCount ?? 0) + 1
            }
            joinGeneration += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatePost(_ postId: String, _ mutate: (inout CommunityPostCard) -> Void) {
        if let index = posts.firstIndex(where: { $0.postId == postId }) {
            mutate(&posts[index])
        }
        if selectedPost?.postId == postId, var updated = selectedPost {
            mutate(&updated)
            selectedPost = updated
        }
    }

    private func vote(_ post: CommunityPostCard, optionId: String) async {
        do {
            let result: VoteResult = try await APIClient.shared.post(
                "/api/posts/\(post.postId)/vote", body: VoteIn(optionId: optionId)
            )
            updatePost(post.postId) { updated in
                updated.poll = result.poll
                updated.myVote = result.myVote
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rsvp(_ post: CommunityPostCard, going: Bool) async {
        do {
            let result: RsvpResult = going
                ? try await APIClient.shared.post("/api/posts/\(post.postId)/rsvp")
                : try await APIClient.shared.delete("/api/posts/\(post.postId)/rsvp")
            updatePost(post.postId) { updated in
                updated.attendeeCount = result.attendeeCount
                updated.myRsvp = result.going
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleActive(_ post: CommunityPostCard) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.patch(
                "/api/communities/me/posts/\(post.postId)",
                body: CommunityPostUpdate(active: !(post.active ?? true))
            )
            selectedPost = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One square grid tile: the post's photo if it has one, otherwise a typed
/// placeholder (kind icon + title snippet) so imageless posts (polls, plain
/// announcements) still show up in the grid instead of being hidden.
private struct PostTile: View {
    let post: CommunityPostCard
    let showUnpublishedBadge: Bool

    private var isUnpublished: Bool { showUnpublishedBadge && post.active == false }

    private var icon: String {
        switch post.kind {
        case "link": "link"
        case "poll": "chart.bar.fill"
        case "event": "calendar"
        default: "megaphone.fill"
        }
    }

    private var kindTint: Color {
        switch post.kind {
        case "link": .blue
        case "poll": .purple
        case "event": .green
        default: .accentColor
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let photo = post.displayPhotos.first {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { RemotePhotoView(photo: photo) }
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(6)
                            .shadow(radius: 2)
                    }
            } else {
                placeholderTile
            }
            if isUnpublished {
                Text("Unpublished")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.orange))
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .opacity(isUnpublished ? 0.55 : 1)
    }

    private var placeholderTile: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    kindTint.opacity(0.15)
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(kindTint)
                        Text(post.title ?? "")
                            .font(.caption2.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                }
            }
            .clipped()
    }
}
