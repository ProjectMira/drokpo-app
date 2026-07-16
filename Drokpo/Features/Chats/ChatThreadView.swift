import FirebaseFirestore
import PhotosUI
import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let imageUrl: String?
    let audioUrl: String?
    let audioDurationSec: Int?
    let createdAt: Date

    var hasMedia: Bool { imageUrl != nil || audioUrl != nil }
}

/// What the input bar is about to send — a message carries exactly one.
private enum ChatDraft {
    case text(String)
    case photo(UIImage)
    case voice(url: URL, seconds: Int)
}

struct ChatThreadView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ChatStore.self) private var chats
    @Environment(\.dismiss) private var dismiss

    let matchId: String

    @State private var messages: [ChatMessage] = []
    @State private var registration: ListenerRegistration?
    /// Last message id we've sent a read receipt for, so snapshot churn
    /// doesn't spam POST /read.
    @State private var lastMarkedMessageId: String?
    @State private var errorMessage: String?
    @State private var showUnmatchConfirm = false
    @State private var showBlockConfirm = false
    @State private var showReportDialog = false
    @State private var viewingImageURL: URL?

    /// The live match entry, looked up by id every render so unread/profile
    /// stay current — and nil during a push deep-link cold start before the
    /// ChatStore listener has delivered this match.
    private var entry: ChatStore.Entry? {
        chats.entries.first { $0.matchId == matchId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            let meta = metadata(at: index)
                            if let day = meta.daySeparator {
                                daySeparator(day)
                            }
                            bubble(message)
                                .id(message.id)
                            if let time = meta.timestamp {
                                timestampCaption(time, isMine: message.senderId == session.uid)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            ChatInputBar { draft in
                await send(draft)
            }
        }
        .navigationTitle(entry?.otherUser?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let other = entry?.otherUser {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        if other.isCommunity {
                            CommunityPageView(cid: other.uid)
                        } else {
                            ProfileDetailView(card: other)
                        }
                    } label: {
                        RemotePhotoView(photo: other.photos?.first)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    }
                }
            }
            if entry != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Unmatch", role: .destructive) { showUnmatchConfirm = true }
                        Button("Block", role: .destructive) { showBlockConfirm = true }
                        Button("Report") { showReportDialog = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear { attachListener() }
        .onDisappear {
            registration?.remove()
            registration = nil
        }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Unmatch?", isPresented: $showUnmatchConfirm, titleVisibility: .visible) {
            Button("Unmatch", role: .destructive) { Task { await unmatch() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer see each other or be able to message.")
        }
        .confirmationDialog("Block this person?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you, and you'll be unmatched.")
        }
        .confirmationDialog("Report this person", isPresented: $showReportDialog, titleVisibility: .visible) {
            ForEach(Vocabulary.reportReasons, id: \.self) { reason in
                Button(reason) { Task { await report(reason: reason) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $viewingImageURL) { url in
            ChatImageViewer(url: url) { viewingImageURL = nil }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderId == session.uid
        return HStack {
            if isMine { Spacer(minLength: 48) }
            bubbleContent(message, isMine: isMine)
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    @ViewBuilder
    private func bubbleContent(_ message: ChatMessage, isMine: Bool) -> some View {
        if let imageUrl = message.imageUrl, let url = URL(string: imageUrl) {
            Button {
                viewingImageURL = url
            } label: {
                Color.clear
                    .frame(width: 220, height: 220)
                    .overlay { RemotePhotoView(photo: Photo(storagePath: "chat-image-\(message.id)", url: imageUrl)) }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .clipped()
            }
            .buttonStyle(.plain)
        } else if let audioUrl = message.audioUrl, let url = URL(string: audioUrl) {
            AudioBubbleView(id: message.id, url: url, durationSec: message.audioDurationSec ?? 0, isOnTintBackground: isMine)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
        } else if let shared = SharedLinkMessage(text: message.text) {
            // A share-sheet message ("<title>\n<drokpo share link>") renders
            // as a tappable card that opens the shared content in-app.
            Button {
                DeepLinkRouter.shared.pendingShare = shared.destination
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Shared \(shared.kindLabel)", systemImage: shared.icon)
                        .font(.caption.bold())
                        .opacity(0.85)
                    if let caption = shared.caption {
                        Text(caption)
                            .font(.body.bold())
                            .multilineTextAlignment(.leading)
                    }
                    Text("Tap to view")
                        .font(.caption2)
                        .opacity(0.7)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
                .foregroundStyle(isMine ? .white : .primary)
            }
            .buttonStyle(.plain)
        } else {
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
                .foregroundStyle(isMine ? .white : .primary)
        }
    }

    // MARK: - Timestamps

    /// What to render around the message at `index`: an optional day-separator
    /// chip above, and an optional time caption below.
    private struct RowMetadata {
        var daySeparator: Date?
        var timestamp: Date?
    }

    private func metadata(at index: Int) -> RowMetadata {
        let message = messages[index]
        var meta = RowMetadata()
        let calendar = Calendar.current
        if index == 0 || !calendar.isDate(message.createdAt, inSameDayAs: messages[index - 1].createdAt) {
            meta.daySeparator = message.createdAt
        }
        if index == messages.count - 1 {
            meta.timestamp = message.createdAt
        } else {
            let next = messages[index + 1]
            // End of a consecutive run from the same sender, or a gap over 10
            // minutes to the next message.
            if next.senderId != message.senderId
                || next.createdAt.timeIntervalSince(message.createdAt) > 600 {
                meta.timestamp = message.createdAt
            }
        }
        return meta
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(daySeparatorText(date))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private func daySeparatorText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func timestampCaption(_ date: Date, isMine: Bool) -> some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private func attachListener() {
        guard registration == nil else { return }
        registration = Firestore.firestore()
            .collection("matches").document(matchId)
            .collection("messages")
            .order(by: "createdAt")
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                messages = (snapshot?.documents ?? []).compactMap { doc in
                    // .estimate resolves pending server timestamps so our own
                    // just-sent messages don't jump around when the write lands.
                    let data = doc.data(with: .estimate)
                    guard let senderId = data["senderId"] as? String,
                          let text = data["text"] as? String else { return nil }
                    return ChatMessage(
                        id: doc.documentID,
                        senderId: senderId,
                        text: text,
                        imageUrl: data["imageUrl"] as? String,
                        audioUrl: data["audioUrl"] as? String,
                        audioDurationSec: data["audioDurationSec"] as? Int,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now
                    )
                }
                markRead()
            }
    }

    private func markRead() {
        // Reads the live entry (not a stale captured copy), so the unread guard
        // reflects the current count.
        guard (entry?.unread ?? 0) > 0 || messages.last?.senderId != session.uid else { return }
        // The listener fires on every snapshot (including our own sends and
        // presence-style updates); only POST when there's actually a new
        // incoming message since the last read receipt.
        guard let lastId = messages.last?.id, lastId != lastMarkedMessageId else { return }
        lastMarkedMessageId = lastId
        chats.clearUnread(matchId: matchId)
        Task {
            let _: EmptyResponse? = try? await APIClient.shared.post("/api/matches/\(matchId)/read")
        }
    }

    /// Uploads media (if any) then writes the message via direct Firestore
    /// write — the security rules verify participation, active status, and
    /// senderId; the on_message_created Cloud Function handles
    /// lastMessage/unreadCount denormalization and the push. A media
    /// message's `text` also carries a placeholder ("📷 Photo"/"🎤 Voice
    /// message") so a build that predates media rendering still shows a
    /// readable bubble instead of an empty one.
    private func send(_ draft: ChatDraft) async {
        guard let uid = session.uid else { return }
        do {
            var data: [String: Any] = [
                "senderId": uid,
                "imageUrl": NSNull(),
                "audioUrl": NSNull(),
                "audioDurationSec": NSNull(),
                "createdAt": FieldValue.serverTimestamp(),
                "readAt": NSNull(),
            ]
            switch draft {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                data["text"] = trimmed
            case .photo(let image):
                let url = try await MediaUploader.uploadChatPhoto(image)
                data["text"] = "📷 Photo"
                data["imageUrl"] = url.absoluteString
            case .voice(let fileURL, let seconds):
                let url = try await MediaUploader.uploadChatAudio(fileURL)
                data["text"] = "🎤 Voice message"
                data["audioUrl"] = url.absoluteString
                data["audioDurationSec"] = seconds
            }
            try await Firestore.firestore()
                .collection("matches").document(matchId)
                .collection("messages")
                .addDocument(data: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Thread actions

    private func unmatch() async {
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/matches/\(matchId)/unmatch")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func block() async {
        guard let otherUid = entry?.otherUid else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(otherUid)")
            BlockStore.shared.record(uid: otherUid, displayName: entry?.otherUser?.displayName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func report(reason: String) async {
        guard let otherUid = entry?.otherUid else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                "/api/reports",
                body: ReportIn(reportedUid: otherUid, reason: reason, note: "")
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Full-screen tap-through for a chat photo — plain black background,
/// scaled-to-fit, tap anywhere to dismiss.
private struct ChatImageViewer: View {
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemotePhotoView(photo: Photo(storagePath: "chat-image-viewer", url: url.absoluteString))
                .aspectRatio(contentMode: .fit)
                .padding()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding()
        }
        .onTapGesture { onDismiss() }
    }
}

/// Text, photo, or voice — pinned under the message list. Voice recording
/// mirrors CommentComposerBar's states (idle/recording/preview) with a
/// longer 120s cap; a photo is picked and sent immediately (no preview step).
private struct ChatInputBar: View {
    let onSend: (ChatDraft) async -> Void

    @State private var draft = ""
    @State private var recorder = AudioRecorder()
    @State private var recordedFile: (url: URL, seconds: Int)?
    @State private var photoSelection: PhotosPickerItem?
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay { if isSending { ProgressView() } }
        .onChange(of: photoSelection) {
            guard let item = photoSelection else { return }
            photoSelection = nil
            Task { await sendPhoto(item) }
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
            sendButton
        } else {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            .disabled(isSending)
            TextField("Message…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.quaternary))
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    recorder.start(maxSeconds: 120) { url, seconds in
                        recordedFile = (url, seconds)
                    }
                } label: {
                    Image(systemName: "mic.fill")
                }
                .disabled(isSending)
            } else {
                sendButton
            }
        }
    }

    private func recordingContent(elapsed: Int) -> some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("\(elapsed)s / 120s").font(.caption.monospacedDigit())
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
            Task { await sendCurrentDraft() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
        }
        .disabled(isSending)
    }

    private func sendCurrentDraft() async {
        isSending = true
        defer { isSending = false }
        if let recordedFile {
            await onSend(.voice(url: recordedFile.url, seconds: recordedFile.seconds))
            self.recordedFile = nil
        } else {
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            await onSend(.text(text))
            draft = ""
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        isSending = true
        defer { isSending = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorMessage = "That photo couldn't be loaded — try picking another one."
            return
        }
        await onSend(.photo(image))
    }
}
