import SwiftUI

/// The Communities tab for person accounts, YouTube-style: the communities
/// you've joined as an avatar rail up top, and below it a single feed of
/// their posts with sponsored cards mixed in (GET /api/communities/home).
/// Discovering new communities lives behind the toolbar button (and inline
/// while you haven't joined any yet).
struct CommunitiesView: View {
    @State private var mine: [CommunityProfile] = []
    @State private var items: [FeedItem] = []
    /// Verified communities to suggest — only fetched while `mine` is empty.
    @State private var discover: [CommunityProfile] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var urlToOpen: URL?

    var body: some View {
        NavigationStack {
            List {
                if mine.isEmpty && !isLoading {
                    discoverSection
                } else {
                    railSection
                }
                feedSection
            }
            .listStyle(.plain)
            .navigationTitle("Communities")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CommunityDirectoryView()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Discover communities")
                }
            }
            .overlay { if isLoading && mine.isEmpty && items.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .task { await load() }
            // Re-fires when popping back from a detail view (unlike .task),
            // so a join/leave there is reflected here immediately.
            .onAppear { if hasLoaded { Task { await load() } } }
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
    }

    // MARK: Sections

    /// Joined communities as a horizontal avatar rail (YouTube-style).
    private var railSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(mine) { community in
                        NavigationLink {
                            CommunityDetailView(cid: community.id, preview: community)
                        } label: {
                            JoinedCommunityAvatar(community: community)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 6)
        }
    }

    /// Shown instead of the rail while the member hasn't joined anything.
    private var discoverSection: some View {
        Section {
            if discover.isEmpty {
                Text("No communities to discover yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(discover) { community in
                            NavigationLink {
                                CommunityDetailView(cid: community.id, preview: community)
                            } label: {
                                DiscoverCommunityCard(community: community)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            }
        } header: {
            Text("Communities to discover")
        } footer: {
            Text("Join a community to see its posts in your feed here.")
        }
    }

    private var feedSection: some View {
        Section {
            if items.isEmpty && !isLoading && !mine.isEmpty {
                Text("Posts from your communities will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    feedRow(item)
                }
            }
        } header: {
            if !mine.isEmpty { Text("From your communities") }
        }
    }

    @ViewBuilder
    private func feedRow(_ item: FeedItem) -> some View {
        switch item {
        case .post(let post):
            CommunityPostContentView(
                post: post,
                onVote: post.kind == "poll" ? { optionId in Task { await vote(post, optionId: optionId) } } : nil,
                onRsvp: post.kind == "event" ? { going in Task { await rsvp(post, going: going) } } : nil,
                onOpenLink: post.url != nil ? { openLink(post.url!, clickPath: "posts/\(post.postId)") } : nil
            )
            .padding(.vertical, 6)
        case .ad(let ad):
            SponsoredFeedRow(ad: ad) {
                if let url = ad.url { openLink(url, clickPath: "ads/\(ad.adId)") }
            }
            .padding(.vertical, 6)
        case .person, .news:
            // The communities feed never serves these; skip defensively.
            EmptyView()
        }
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let home: CommunitiesHomeResponse = try await APIClient.shared.get("/api/communities/home")
            mine = home.communities ?? []
            items = home.items ?? []
            if mine.isEmpty {
                let response: CommunityListResponse = try await APIClient.shared.get(
                    "/api/communities", query: [URLQueryItem(name: "limit", value: "20")]
                )
                discover = response.communities ?? []
            }
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openLink(_ url: URL, clickPath: String) {
        urlToOpen = url
        Task {
            let _: EmptyResponse? = try? await APIClient.shared.post(
                "/api/\(clickPath)/events", body: ContentEventIn(event: "click")
            )
        }
    }

    private func updatePost(_ postId: String, _ mutate: (inout CommunityPostCard) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == "post-\(postId)" }),
              case .post(var post) = items[index] else { return }
        mutate(&post)
        items[index] = .post(post)
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
}

/// A joined community in the rail: circular logo with the name underneath,
/// like a YouTube subscription avatar.
private struct JoinedCommunityAvatar: View {
    let community: CommunityProfile

    var body: some View {
        VStack(spacing: 6) {
            RemotePhotoView(photo: community.photos?.first)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            Text(community.name ?? "—")
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}

/// A sponsored card inside the communities feed.
private struct SponsoredFeedRow: View {
    let ad: AdCard
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sponsored")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            if let photo = ad.displayPhotos.first {
                PhotoBand(photo: photo)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(ad.title ?? "—").font(.headline)
            if let body = ad.body, !body.isEmpty {
                Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            Button(ad.ctaLabel?.isEmpty == false ? ad.ctaLabel! : "Learn more") {
                onOpen()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Full "see all" list of verified communities, with join/leave inline.
struct CommunityDirectoryView: View {
    @State private var communities: [CommunityProfile] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var workingCid: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if communities.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No communities yet",
                    systemImage: "person.3",
                    description: Text("Verified communities will show up here.")
                )
            } else {
                ForEach(communities) { community in
                    NavigationLink {
                        CommunityDetailView(cid: community.id, preview: community)
                    } label: {
                        HStack {
                            CommunityRow(community: community)
                            Spacer()
                            joinButton(community)
                        }
                    }
                }
            }
        }
        .navigationTitle("Discover communities")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && communities.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
        .onAppear { if hasLoaded { Task { await load() } } }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Inline join/leave — .bordered keeps the button independently tappable
    /// inside the row's NavigationLink.
    private func joinButton(_ community: CommunityProfile) -> some View {
        Button {
            Task { await toggleJoin(community) }
        } label: {
            if workingCid == community.id {
                ProgressView().controlSize(.small)
            } else {
                Text(community.joined == true ? "Joined" : "Join")
                    .font(.subheadline.bold())
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(community.joined == true ? .secondary : .accentColor)
        .disabled(workingCid != nil)
    }

    private func toggleJoin(_ community: CommunityProfile) async {
        workingCid = community.id
        defer { workingCid = nil }
        let wasJoined = community.joined == true
        do {
            let _: EmptyResponse = wasJoined
                ? try await APIClient.shared.delete("/api/communities/\(community.id)/join")
                : try await APIClient.shared.post("/api/communities/\(community.id)/join")
            if let index = communities.firstIndex(where: { $0.id == community.id }) {
                communities[index].joined = !wasJoined
                let delta = wasJoined ? -1 : 1
                communities[index].memberCount = max(0, (communities[index].memberCount ?? 0) + delta)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: CommunityListResponse = try await APIClient.shared.get(
                "/api/communities", query: [URLQueryItem(name: "limit", value: "50")]
            )
            communities = response.communities ?? []
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shared cells

struct CommunityRow: View {
    let community: CommunityProfile

    var body: some View {
        HStack(spacing: 12) {
            RemotePhotoView(photo: community.photos?.first)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(community.name ?? "Community")
                        .font(.headline)
                    if community.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                            .font(.caption)
                    }
                }
                Text("\(community.memberCount ?? 0) member\((community.memberCount ?? 0) == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DiscoverCommunityCard: View {
    let community: CommunityProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemotePhotoView(photo: community.photos?.first)
                .frame(width: 120, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(community.name ?? "Community")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(community.memberCount ?? 0) member\((community.memberCount ?? 0) == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }
}
