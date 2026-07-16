import SwiftUI

/// Network + list state for one post's comments — top-level comments plus
/// lazily-loaded reply threads, mirroring FeedModel's role for the deck.
@Observable
final class CommentsModel {
    let postId: String
    /// The post's owning community uid — lets the viewer delete any comment
    /// on their own post (server-enforced too; this only drives the UI).
    let postOwnerCid: String?
    private let myUid: String?

    var comments: [CommentCard] = []
    var repliesByParent: [String: [CommentCard]] = [:]
    var expandedParents: Set<String> = []
    var isLoading = true
    var isLoadingMore = false
    var hasMore = true
    var errorMessage: String?

    init(postId: String, postOwnerCid: String?, myUid: String?) {
        self.postId = postId
        self.postOwnerCid = postOwnerCid
        self.myUid = myUid
    }

    func canDelete(_ comment: CommentCard) -> Bool {
        guard let myUid else { return false }
        return comment.authorUid == myUid || myUid == postOwnerCid
    }

    func isMine(_ comment: CommentCard) -> Bool {
        myUid != nil && comment.authorUid == myUid
    }

    @MainActor
    func reportAuthor(_ comment: CommentCard, reason: String) async {
        guard let authorUid = comment.authorUid else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                "/api/reports",
                body: ReportIn(
                    reportedUid: authorUid,
                    reason: reason,
                    note: "Comment \(comment.commentId) on post \(postId)"
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Blocks the comment's author, then reloads — the backend drops blocked
    /// authors' comments from the list, so their content disappears too.
    @MainActor
    func blockAuthor(_ comment: CommentCard) async {
        guard let authorUid = comment.authorUid else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(authorUid)")
            BlockStore.shared.record(uid: authorUid, displayName: comment.authorName)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func load() async {
        isLoading = comments.isEmpty
        hasMore = true
        do {
            let response: CommentsResponse = try await APIClient.shared.get("/api/posts/\(postId)/comments")
            comments = response.comments ?? []
            hasMore = !comments.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func loadMoreIfNeeded(current: CommentCard) {
        guard hasMore, !isLoadingMore, current.id == comments.last?.id else { return }
        Task { await loadMore() }
    }

    @MainActor
    private func loadMore() async {
        guard let lastId = comments.last?.commentId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response: CommentsResponse = try await APIClient.shared.get(
                "/api/posts/\(postId)/comments", query: [URLQueryItem(name: "before", value: lastId)]
            )
            let fresh = response.comments ?? []
            hasMore = !fresh.isEmpty
            comments.append(contentsOf: fresh)
        } catch {
            // Silent — a pagination hiccup shouldn't interrupt reading comments.
        }
    }

    @MainActor
    func toggleReplies(for parentId: String) async {
        if expandedParents.contains(parentId) {
            expandedParents.remove(parentId)
            return
        }
        expandedParents.insert(parentId)
        guard repliesByParent[parentId] == nil else { return }
        do {
            let response: RepliesResponse = try await APIClient.shared.get(
                "/api/posts/\(postId)/comments/\(parentId)/replies"
            )
            repliesByParent[parentId] = response.replies ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Uploads audio if needed, posts the comment, and inserts it locally
    /// (top of the list for a top-level comment, end of the thread for a
    /// reply). Returns whether it succeeded, so the composer can clear itself.
    @MainActor
    func submit(_ draft: CommentDraft, parentId: String?) async -> Bool {
        do {
            let payload: CommentIn
            switch draft {
            case .text(let text):
                guard !text.isEmpty else { return false }
                payload = CommentIn(text: text, parentId: parentId)
            case .audio(let url, let seconds):
                let storagePath = try await MediaUploader.uploadCommentAudio(url)
                payload = CommentIn(audioStoragePath: storagePath, audioDurationSec: seconds, parentId: parentId)
            }
            let created: CommentCard = try await APIClient.shared.post("/api/posts/\(postId)/comments", body: payload)
            if let parentId {
                repliesByParent[parentId, default: []].append(created)
                bumpReplyCount(parentId, by: 1)
                expandedParents.insert(parentId)
            } else {
                comments.insert(created, at: 0)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func delete(_ comment: CommentCard) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.delete(
                "/api/posts/\(postId)/comments/\(comment.commentId)"
            )
            if let parentId = comment.parentId {
                repliesByParent[parentId]?.removeAll { $0.commentId == comment.commentId }
                bumpReplyCount(parentId, by: -1)
            } else {
                comments.removeAll { $0.commentId == comment.commentId }
                repliesByParent[comment.commentId] = nil
                expandedParents.remove(comment.commentId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func vote(_ comment: CommentCard, value: String?) async {
        do {
            let result: CommentVoteResult
            if let value {
                result = try await APIClient.shared.put(
                    "/api/posts/\(postId)/comments/\(comment.commentId)/vote", body: CommentVoteIn(value: value)
                )
            } else {
                result = try await APIClient.shared.delete("/api/posts/\(postId)/comments/\(comment.commentId)/vote")
            }
            update(comment.commentId) { updated in
                updated.likeCount = result.likeCount
                updated.dislikeCount = result.dislikeCount
                updated.myVote = result.myVote
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bumpReplyCount(_ parentId: String, by delta: Int) {
        update(parentId) { updated in
            updated.replyCount = max(0, (updated.replyCount ?? 0) + delta)
        }
    }

    private func update(_ commentId: String, _ mutate: (inout CommentCard) -> Void) {
        if let index = comments.firstIndex(where: { $0.commentId == commentId }) {
            mutate(&comments[index])
            return
        }
        for (parentId, replies) in repliesByParent {
            guard let index = replies.firstIndex(where: { $0.commentId == commentId }) else { continue }
            var updatedReplies = replies
            mutate(&updatedReplies[index])
            repliesByParent[parentId] = updatedReplies
            return
        }
    }
}

/// What the composer bar is about to send — a comment carries exactly one.
enum CommentDraft {
    case text(String)
    case audio(url: URL, seconds: Int)
}

/// Instagram-style comments on a community post: a list of top-level
/// comments (newest first) with one level of lazily-loaded replies, and a
/// composer that accepts text or a voice recording.
struct CommentsSheet: View {
    let post: CommunityPostCard
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: CommentsModel
    @State private var replyTarget: CommentCard?
    /// Long-pressed comment awaiting a report/block choice, then (if
    /// "Report…" was picked) a reason.
    @State private var safetyTarget: CommentCard?
    @State private var reportTarget: CommentCard?

    init(post: CommunityPostCard) {
        self.post = post
        // SessionStore isn't available at init time (no @Environment access
        // outside body/task) — rebuilt with the real uid in .task below,
        // which fires exactly once per sheet presentation.
        _model = State(initialValue: CommentsModel(postId: post.postId, postOwnerCid: post.communityId, myUid: nil))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                list
                CommentComposerBar(
                    replyingTo: replyTarget?.authorName,
                    onCancelReply: { replyTarget = nil }
                ) { draft in
                    let parentId = replyTarget?.commentId
                    let success = await model.submit(draft, parentId: parentId)
                    if success { replyTarget = nil }
                    return success
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                model = CommentsModel(postId: post.postId, postOwnerCid: post.communityId, myUid: session.uid)
                await model.load()
            }
            .alert("Something went wrong", isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .confirmationDialog(
                "Comment by \(safetyTarget?.authorName ?? "member")",
                isPresented: .init(
                    get: { safetyTarget != nil },
                    set: { if !$0 { safetyTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Report…", role: .destructive) { reportTarget = safetyTarget }
                Button("Block \(safetyTarget?.authorName ?? "member")", role: .destructive) {
                    if let target = safetyTarget {
                        Task { await model.blockAuthor(target) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Why are you reporting this comment?",
                isPresented: .init(
                    get: { reportTarget != nil },
                    set: { if !$0 { reportTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(Vocabulary.reportReasons, id: \.self) { reason in
                    Button(reason, role: .destructive) {
                        if let target = reportTarget {
                            Task { await model.reportAuthor(target, reason: reason) }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.isLoading {
            ProgressView().frame(maxHeight: .infinity)
        } else if model.comments.isEmpty {
            emptyState
        } else {
            List {
                ForEach(model.comments) { comment in
                    commentRow(comment)
                        .onAppear { model.loadMoreIfNeeded(current: comment) }
                }
                if model.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.load() }
        }
    }

    private func commentRow(_ comment: CommentCard) -> some View {
        CommentRow(
            comment: comment,
            isExpanded: model.expandedParents.contains(comment.id),
            replies: model.repliesByParent[comment.id],
            canDelete: model.canDelete(comment),
            onReply: { replyTarget = comment },
            onToggleReplies: { Task { await model.toggleReplies(for: comment.id) } },
            onVote: { value in Task { await model.vote(comment, value: value) } },
            onDelete: { Task { await model.delete(comment) } },
            onSafety: model.isMine(comment) ? nil : { safetyTarget = comment },
            replyActions: { reply in
                ReplyRowActions(
                    canDelete: model.canDelete(reply),
                    onVote: { value in Task { await model.vote(reply, value: value) } },
                    onDelete: { Task { await model.delete(reply) } },
                    onSafety: model.isMine(reply) ? nil : { safetyTarget = reply }
                )
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No comments yet")
                .font(.headline)
            Text("Be the first to say something.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Closures scoped to one specific reply — bundled so CommentRow can build
/// them per-reply without threading a pile of comment-specific parameters.
private struct ReplyRowActions {
    let canDelete: Bool
    let onVote: (String?) -> Void
    let onDelete: () -> Void
    /// Report/block the reply's author; nil for the viewer's own replies.
    let onSafety: (() -> Void)?
}

private struct CommentRow: View {
    let comment: CommentCard
    let isExpanded: Bool
    let replies: [CommentCard]?
    let canDelete: Bool
    let onReply: () -> Void
    let onToggleReplies: () -> Void
    let onVote: (String?) -> Void
    let onDelete: () -> Void
    /// Report/block the comment's author; nil for the viewer's own comments.
    let onSafety: (() -> Void)?
    let replyActions: (CommentCard) -> ReplyRowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                CommentHeader(comment: comment)
                CommentBody(comment: comment)
                    .padding(.leading, 40)
            }
            .contentShape(Rectangle())
            .contextMenu {
                if let onSafety {
                    Button("Report or block…", systemImage: "exclamationmark.bubble", role: .destructive, action: onSafety)
                }
            }
            actionsRow
                .padding(.leading, 40)
            repliesDisclosure
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if canDelete {
                Button("Delete", role: .destructive) { onDelete() }
            }
            if let onSafety {
                Button("Report", action: onSafety)
                    .tint(.orange)
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 16) {
            Button("Reply", action: onReply)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            VoteButtons(myVote: comment.myVote, likeCount: comment.likeCount ?? 0, dislikeCount: comment.dislikeCount ?? 0, onVote: onVote)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var repliesDisclosure: some View {
        let replyCount = comment.replyCount ?? 0
        if isExpanded {
            if let replies {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(replies) { reply in
                        let actions = replyActions(reply)
                        ReplyRow(
                            reply: reply,
                            canDelete: actions.canDelete,
                            onVote: actions.onVote,
                            onDelete: actions.onDelete,
                            onSafety: actions.onSafety
                        )
                    }
                }
                .padding(.leading, 40)
                .padding(.top, 4)
            } else {
                ProgressView().padding(.leading, 40)
            }
        } else if replyCount > 0 {
            Button {
                onToggleReplies()
            } label: {
                Text("View \(replyCount) repl\(replyCount == 1 ? "y" : "ies")")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 40)
        }
    }
}

private struct ReplyRow: View {
    let reply: CommentCard
    let canDelete: Bool
    let onVote: (String?) -> Void
    let onDelete: () -> Void
    let onSafety: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                CommentHeader(comment: reply, avatarSize: 26)
                CommentBody(comment: reply)
                    .padding(.leading, 34)
            }
            .contentShape(Rectangle())
            .contextMenu {
                if let onSafety {
                    Button("Report or block…", systemImage: "exclamationmark.bubble", role: .destructive, action: onSafety)
                }
            }
            VoteButtons(myVote: reply.myVote, likeCount: reply.likeCount ?? 0, dislikeCount: reply.dislikeCount ?? 0, onVote: onVote)
                .padding(.leading, 34)
        }
        .swipeActions(edge: .trailing) {
            if canDelete {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

private struct CommentHeader: View {
    let comment: CommentCard
    var avatarSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 8) {
            RemotePhotoView(photo: comment.authorPhoto)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(comment.authorName ?? "—").font(.subheadline.bold())
                    if comment.isCommunityAuthor {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
                if let relative = comment.relativeCreated {
                    Text(relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CommentBody: View {
    let comment: CommentCard

    var body: some View {
        if let text = comment.text, !text.isEmpty {
            Text(text).font(.subheadline)
        } else if let url = comment.audioURL {
            AudioBubbleView(id: comment.id, url: url, durationSec: comment.audioDurationSec ?? 0)
        }
    }
}

private struct VoteButtons: View {
    let myVote: String?
    let likeCount: Int
    let dislikeCount: Int
    let onVote: (String?) -> Void

    var body: some View {
        HStack(spacing: 16) {
            button(regular: "hand.thumbsup", filled: "hand.thumbsup.fill", isActive: myVote == "like", count: likeCount) {
                onVote(myVote == "like" ? nil : "like")
            }
            button(regular: "hand.thumbsdown", filled: "hand.thumbsdown.fill", isActive: myVote == "dislike", count: dislikeCount) {
                onVote(myVote == "dislike" ? nil : "dislike")
            }
        }
        .buttonStyle(.plain)
    }

    private func button(regular: String, filled: String, isActive: Bool, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isActive ? filled : regular)
                if count > 0 {
                    Text("\(count)").font(.caption2)
                }
            }
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
    }
}

/// Text or voice, idle/recording/preview — pinned under the comments list.
private struct CommentComposerBar: View {
    var replyingTo: String?
    var onCancelReply: () -> Void
    var onSend: (CommentDraft) async -> Bool

    @State private var draftText = ""
    @State private var recorder = AudioRecorder()
    @State private var recordedFile: (url: URL, seconds: Int)?
    @State private var isSending = false

    private var canSend: Bool {
        !isSending && (recordedFile != nil || !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let replyingTo {
                replyChip(replyingTo)
            }
            HStack(spacing: 8) {
                content
                if canSend {
                    sendButton
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func replyChip(_ name: String) -> some View {
        HStack {
            Text("Replying to \(name)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action: onCancelReply) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch recorder.state {
        case .idle:
            idleContent
        case .recording(let elapsed):
            recordingContent(elapsed: elapsed)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if let recordedFile {
            AudioBubbleView(id: "draft-\(recordedFile.url.lastPathComponent)", url: recordedFile.url, durationSec: recordedFile.seconds)
            Button {
                try? FileManager.default.removeItem(at: recordedFile.url)
                self.recordedFile = nil
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
        } else {
            TextField("Add a comment…", text: $draftText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.quaternary))
            Button {
                recorder.start(maxSeconds: 60) { url, seconds in
                    recordedFile = (url, seconds)
                }
            } label: {
                Image(systemName: "mic.fill")
            }
        }
    }

    private func recordingContent(elapsed: Int) -> some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("\(elapsed)s / 60s").font(.caption.monospacedDigit())
            Spacer()
            Button {
                recorder.cancel()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            Button {
                if let result = recorder.stop() {
                    recordedFile = result
                }
            } label: {
                Image(systemName: "stop.circle.fill").foregroundStyle(.red)
            }
        }
    }

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            if isSending {
                ProgressView()
            } else {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
            }
        }
        .disabled(isSending)
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        let draft: CommentDraft = recordedFile.map { .audio(url: $0.url, seconds: $0.seconds) }
            ?? .text(draftText.trimmingCharacters(in: .whitespacesAndNewlines))
        if await onSend(draft) {
            draftText = ""
            recordedFile = nil
        }
    }
}
