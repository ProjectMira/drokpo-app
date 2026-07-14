import SwiftUI

struct FeedView: View {
    @State private var model = FeedModel()
    @State private var expandedCard: FeedCard?
    @State private var expandedNews: NewsCard?
    @State private var expandedPost: CommunityPostCard?
    /// Set instead of model.urlToOpen while a detail sheet is up — swapping
    /// two sheets in one transaction is flaky; the Safari sheet presents from
    /// the detail sheet's onDismiss instead.
    @State private var pendingURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                if model.isLoading {
                    ProgressView()
                } else if model.deck.isEmpty {
                    emptyState
                } else {
                    deck
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.undoLastSwipe()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .disabled(!model.canUndo)
                    .accessibilityLabel("Undo last swipe")
                }
            }
            .task { await model.loadInitial() }
            .onChange(of: model.deck.first?.id) { model.reportTopImpressionIfNeeded() }
            .overlay {
                if let matched = model.matchedCard {
                    MatchOverlay(card: matched) { model.matchedCard = nil }
                }
            }
            .alert("Something went wrong", isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .sheet(item: $expandedCard) { card in
                NavigationStack {
                    ProfileDetailView(
                        card: card,
                        context: .discover(
                            onLike: {
                                expandedCard = nil
                                model.swipe(card, action: .like)
                            },
                            onPass: {
                                expandedCard = nil
                                model.swipe(card, action: .pass)
                            }
                        )
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { expandedCard = nil }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(item: $model.urlToOpen) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
            .sheet(item: $expandedNews, onDismiss: presentPendingURL) { item in
                NewsDetailSheet(item: item) {
                    model.reportNewsClick(item)
                    pendingURL = item.url
                    expandedNews = nil
                }
                .presentationDetents([.large])
            }
            .sheet(item: $expandedPost, onDismiss: presentPendingURL) { post in
                CommunityPostDetailSheet(
                    post: post,
                    onVote: { optionId in
                        Task {
                            if let updated = await model.vote(on: post, optionId: optionId) {
                                expandedPost = updated
                            }
                        }
                    },
                    onRsvp: { going in
                        Task {
                            if let updated = await model.rsvp(on: post, going: going) {
                                expandedPost = updated
                            }
                        }
                    },
                    onOpenLink: post.url.map { url in
                        { model.reportPostClick(post); pendingURL = url; expandedPost = nil }
                    }
                )
                .presentationDetents([.medium, .large])
                // The root alert can't present while this sheet is up — a
                // failed vote/RSVP must surface here, not silently no-op.
                .alert("Something went wrong", isPresented: .init(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
            }
        }
    }

    /// Presents a link queued by a detail sheet once that sheet is fully
    /// dismissed (sheet-over-sheet swaps in one transaction are unreliable).
    private func presentPendingURL() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        model.urlToOpen = url
    }

    /// Tinder-style deck: the card fills the available space edge-to-edge and
    /// the pass/like buttons float over its bottom instead of sitting below.
    private var deck: some View {
        ZStack {
            // Top 3 cards; the last in this array renders on top.
            ForEach(Array(model.deck.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                deckCard(item, isTop: index == 0)
                    .scaleEffect(1 - CGFloat(index) * 0.03)
                    .offset(y: CGFloat(index) * 10)
            }
        }
        .overlay(alignment: .bottom) {
            SwipeActionButtons(
                onPass: { topSwipe(liked: false) },
                onLike: { topSwipe(liked: true) }
            )
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func deckCard(_ item: DeckItem, isTop: Bool) -> some View {
        switch item {
        case .profile(let card):
            SwipeableCard(
                card: card,
                isTop: isTop,
                onSwipe: { action in model.swipe(card, action: action) },
                onExpand: { expandedCard = card },
                onReport: { reason in model.reportAndRemove(card, reason: reason) },
                onBlock: { model.blockAndRemove(card) }
            )
        case .ad(let ad):
            SwipeableAdCard(
                ad: ad,
                isTop: isTop,
                onSwipe: { liked in model.swipeAd(ad, liked: liked) }
            )
        case .news(let item):
            SwipeableNewsCard(
                item: item,
                isTop: isTop,
                onSwipe: { liked in model.swipeNews(item, liked: liked) },
                onOpenSource: { model.openNews(item) },
                onExpand: { expandedNews = item }
            )
        case .post(let post):
            SwipeableCommunityPostCard(
                post: post,
                isTop: isTop,
                onSwipe: { liked in model.swipePost(post, liked: liked) },
                onOpenLink: { model.openPostLink(post) },
                onExpand: { expandedPost = post }
            )
        }
    }

    /// Route the pass/like buttons to whatever sits on top of the deck.
    private func topSwipe(liked: Bool) {
        switch model.deck.first {
        case .profile(let card):
            model.swipe(card, action: liked ? .like : .pass)
        case .ad(let ad):
            model.swipeAd(ad, liked: liked)
        case .news(let item):
            model.swipeNews(item, liked: liked)
        case .post(let post):
            model.swipePost(post, liked: liked)
        case nil:
            break
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No one new right now")
                .font(.headline)
            Text("Check back later, or widen your preferences in your profile.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Refresh") {
                Task { await model.fetchMore() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

/// Drag gesture, fly-off animation, and LIKE/PASS stamps shared by profile
/// and sponsored cards. `likeLabel` lets the ad card stamp "VISIT" instead.
private struct SwipeableWrapper<Content: View>: View {
    let isTop: Bool
    var likeLabel = "LIKE"
    let onSwipe: (_ liked: Bool) -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGSize = .zero

    private let swipeThreshold: CGFloat = 110

    var body: some View {
        content()
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 18)))
            .overlay(alignment: .topLeading) { stamp(likeLabel, color: .brandRed, visible: offset.width > 40) }
            .overlay(alignment: .topTrailing) { stamp("PASS", color: .accentColor, visible: offset.width < -40) }
            .gesture(isTop ? dragGesture : nil)
            .animation(.spring(duration: 0.3), value: offset)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                if value.translation.width > swipeThreshold {
                    offset = CGSize(width: 600, height: value.translation.height)
                    onSwipe(true)
                } else if value.translation.width < -swipeThreshold {
                    offset = CGSize(width: -600, height: value.translation.height)
                    onSwipe(false)
                } else {
                    offset = .zero
                }
            }
    }

    private func stamp(_ text: String, color: Color, visible: Bool) -> some View {
        Text(text)
            .font(.title.bold())
            .foregroundStyle(color)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(text == "PASS" ? 15 : -15))
            .opacity(visible ? 1 : 0)
            .padding(24)
    }
}

private struct SwipeableCard: View {
    let card: FeedCard
    let isTop: Bool
    let onSwipe: (SwipeAction) -> Void
    let onExpand: () -> Void
    let onReport: (String) -> Void
    let onBlock: () -> Void

    @State private var showSafetySheet = false
    @State private var showReportReasons = false

    var body: some View {
        SwipeableWrapper(isTop: isTop, onSwipe: { liked in onSwipe(liked ? .like : .pass) }) {
            CardView(card: card, onSafetyTapped: { showSafetySheet = true }, onExpand: isTop ? onExpand : nil)
        }
        .confirmationDialog("Safety", isPresented: $showSafetySheet) {
            Button("Report", role: .destructive) { showReportReasons = true }
            Button("Block", role: .destructive) { onBlock() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Why are you reporting this profile?", isPresented: $showReportReasons, titleVisibility: .visible) {
            ForEach(Vocabulary.reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) { onReport(reason) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SwipeableAdCard: View {
    let ad: AdCard
    let isTop: Bool
    /// liked == true opens the ad link in the in-app browser.
    let onSwipe: (_ liked: Bool) -> Void

    var body: some View {
        SwipeableWrapper(isTop: isTop, likeLabel: "VISIT", onSwipe: onSwipe) {
            AdCardView(ad: ad, onOpen: isTop ? { onSwipe(true) } : nil)
        }
    }
}

private struct SwipeableNewsCard: View {
    let item: NewsCard
    let isTop: Bool
    /// liked == true SAVES the story to the Likes tab.
    let onSwipe: (_ liked: Bool) -> Void
    /// Opens the source article in the in-app browser (arrow button).
    let onOpenSource: () -> Void
    let onExpand: () -> Void

    var body: some View {
        SwipeableWrapper(isTop: isTop, likeLabel: "SAVE", onSwipe: onSwipe) {
            NewsCardView(
                item: item,
                onOpen: isTop ? onOpenSource : nil,
                onExpand: isTop ? onExpand : nil
            )
        }
    }
}

private struct SwipeableCommunityPostCard: View {
    let post: CommunityPostCard
    let isTop: Bool
    /// liked == true SAVES the post to the Likes tab (and RSVPs for events).
    let onSwipe: (_ liked: Bool) -> Void
    /// Opens the post's link in the in-app browser (CTA button).
    let onOpenLink: () -> Void
    let onExpand: () -> Void

    private var likeLabel: String {
        post.kind == "event" ? "JOIN" : "SAVE"
    }

    var body: some View {
        SwipeableWrapper(isTop: isTop, likeLabel: likeLabel, onSwipe: onSwipe) {
            CommunityPostCardView(
                post: post,
                onOpen: isTop && (post.kind == "event" || post.url != nil)
                    ? (post.url != nil ? onOpenLink : { onSwipe(true) })
                    : nil,
                onExpand: isTop ? onExpand : nil
            )
        }
    }
}

/// Tap-through detail for a news card: full summary, source attribution, and
/// a button to open the source article in the in-app browser. The image is a
/// PhotoBand — a fixed-aspect, clipped container — because an unclipped
/// scaled-to-fill photo once inflated this whole sheet wider than the screen.
private struct NewsDetailSheet: View {
    let item: NewsCard
    let onReadFullStory: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let photo = item.displayPhotos.first {
                        PhotoBand(photo: photo)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    HStack(spacing: 6) {
                        if let sourceName = item.sourceName, !sourceName.isEmpty {
                            Text(sourceName.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        if let relative = item.relativePublished {
                            Text("· \(relative)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(item.title ?? "—")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.summary?.isEmpty == false ? item.summary! : item.gist ?? "")
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        onReadFullStory()
                    } label: {
                        Text("Read the full story")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("News")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// Tap-through detail for a community post: full body, poll voting (if a
/// poll), RSVPing (if an event), and a link CTA (if it has one).
private struct CommunityPostDetailSheet: View {
    let post: CommunityPostCard
    let onVote: (String) -> Void
    let onRsvp: (Bool) -> Void
    let onOpenLink: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                CommunityPostContentView(post: post, onVote: onVote, onRsvp: onRsvp, onOpenLink: onOpenLink)
                    .padding()
            }
            .navigationTitle(post.communityName ?? "Community post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct MatchOverlay: View {
    let card: FeedCard
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("It's a match!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                RemotePhotoView(photo: card.photos?.first)
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
                Text("You and \(card.displayName ?? "they") like each other.")
                    .foregroundStyle(.white)
                Button("Keep swiping") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onTapGesture { dismiss() }
    }
}
