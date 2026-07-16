import SwiftUI

/// Renders one community post's content — used both in a community's own
/// post feed/page (CommunityPageView, CommunitiesView) and, interleaved, in the Discover deck
/// (FeedView/CardView) — so the two surfaces stay visually consistent.
struct CommunityPostContentView: View {
    let post: CommunityPostCard
    /// Called with the tapped option id; nil disables voting (e.g. read-only
    /// contexts). The caller owns the network call and updates `post`.
    var onVote: ((String) -> Void)?
    /// Called with `going`; nil disables RSVPing. The caller owns the
    /// network call and updates `post`.
    var onRsvp: ((Bool) -> Void)?
    /// Called when the link CTA is tapped; nil hides the button.
    var onOpenLink: (() -> Void)?
    /// Called when the comment button is tapped; nil hides the button (e.g.
    /// the compact deck card, where comments live one tap away in the sheet).
    var onOpenComments: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let photo = post.displayPhotos.first {
                // Fixed-aspect clipped band — an unclipped fill image inflates
                // the surrounding layout (see PhotoBand).
                PhotoBand(photo: photo)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let title = post.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if post.kind == "event" {
                EventDetailsView(post: post, onRsvp: onRsvp)
            }
            if let body = post.body, !body.isEmpty {
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
            if post.kind == "poll", let poll = post.poll {
                PollOptionsView(poll: poll, myVote: post.myVote, onVote: onVote)
            }
            if post.url != nil, let onOpenLink {
                Button(post.ctaLabel?.isEmpty == false ? post.ctaLabel! : "Learn more") {
                    onOpenLink()
                }
                .buttonStyle(.borderedProminent)
            }
            if let onOpenComments {
                commentButton(onOpenComments)
            }
        }
    }

    private func commentButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.right")
                Text(post.commentCount.map { $0 > 0 ? "\($0)" : "Comment" } ?? "Comment")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Tappable when the post carries a communityId — every call site
    /// (CommunitiesView's feed, LikesView's saved-post detail, and
    /// CommunityPostDetailSheet, which owns its own NavigationStack) sits
    /// inside a navigation context this can push onto.
    @ViewBuilder
    private var header: some View {
        if let cid = post.communityId {
            NavigationLink {
                CommunityPageView(cid: cid)
            } label: {
                headerContent
            }
            .buttonStyle(.plain)
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack(spacing: 8) {
            RemotePhotoView(photo: post.communityLogoUrl.map { Photo(storagePath: "logo-\(post.postId)", url: $0) })
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            Text(post.communityName ?? "Community")
                .font(.subheadline.bold())
            // Signal the header is a link to the community's page.
            if post.communityId != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// Date/location chips plus the Join/Can't come button for an event post.
private struct EventDetailsView: View {
    let post: CommunityPostCard
    var onRsvp: ((Bool) -> Void)?

    private var goingCount: Int { post.attendeeCount ?? 0 }
    private var isGoing: Bool { post.myRsvp ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = post.eventDate {
                Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.subheadline)
            }
            if let location = post.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(goingCount) going")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                rsvpButton
            }
        }
    }

    @ViewBuilder
    private var rsvpButton: some View {
        if let onRsvp {
            if isGoing {
                Button("Can't come") { onRsvp(false) }
                    .buttonStyle(.bordered)
            } else {
                Button("Join") { onRsvp(true) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Tap-through detail for a community post: full body, poll voting (if a
/// poll), RSVPing (if an event), a link CTA (if it has one), and — in owner
/// mode — a publish/unpublish toggle. Shared by the Discover deck
/// (FeedView) and the community's own page (CommunityPageView) so both
/// surfaces render a post identically.
struct CommunityPostDetailSheet: View {
    let post: CommunityPostCard
    var ownerMode = false
    let onVote: ((String) -> Void)?
    let onRsvp: ((Bool) -> Void)?
    let onOpenLink: (() -> Void)?
    var onTogglePublish: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showComments = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CommunityPostContentView(
                        post: post, onVote: onVote, onRsvp: onRsvp, onOpenLink: onOpenLink,
                        onOpenComments: { showComments = true }
                    )
                    if ownerMode {
                        ownerControls
                    }
                }
                .padding()
            }
            .navigationTitle(post.communityName ?? "Community post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
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

    @ViewBuilder
    private var ownerControls: some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            if post.active == false {
                Label("Unpublished — only you can see this", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if let onTogglePublish {
                Button(post.active == false ? "Republish" : "Unpublish") {
                    onTogglePublish()
                }
                .buttonStyle(.bordered)
                .tint(post.active == false ? .green : .orange)
            }
        }
    }
}

/// Tappable poll options that animate to a percentage bar once the caller
/// has voted (myVote != nil) or after a vote is cast. Voting again on a
/// different option changes the vote (the backend moves the count); only
/// the currently-selected option is disabled.
private struct PollOptionsView: View {
    let poll: Poll
    let myVote: String?
    var onVote: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(poll.options) { option in
                Button {
                    onVote?(option.id)
                } label: {
                    optionRow(option)
                }
                .buttonStyle(.plain)
                .disabled(onVote == nil || myVote == option.id)
            }
            if poll.totalVotes > 0 {
                Text("\(poll.totalVotes) vote\(poll.totalVotes == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: PollOption) -> some View {
        let hasVoted = myVote != nil
        let isMine = myVote == option.id
        let percentage = poll.percentage(for: option.id)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
            if hasVoted {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isMine ? Color.accentColor.opacity(0.35) : .secondary.opacity(0.2))
                        .frame(width: geometry.size.width * percentage)
                }
            }
            HStack {
                Text(option.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if isMine {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
                Spacer()
                if hasVoted {
                    Text("\(Int((percentage * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
    }
}
