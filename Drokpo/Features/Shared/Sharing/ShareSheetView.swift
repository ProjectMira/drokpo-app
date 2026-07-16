import FirebaseFirestore
import SwiftUI

/// Writes chat messages from outside ChatThreadView (the share sheet's
/// "send to a match" rows). Same direct-Firestore contract as
/// ChatThreadView.send: the security rules verify participation, active
/// status, and senderId; the on_message_created Cloud Function handles
/// lastMessage/unreadCount denormalization and the push.
enum ChatMessageSender {
    static func sendText(_ text: String, matchId: String, senderId: String) async throws {
        let data: [String: Any] = [
            "senderId": senderId,
            "text": text,
            "imageUrl": NSNull(),
            "audioUrl": NSNull(),
            "audioDurationSec": NSNull(),
            "createdAt": FieldValue.serverTimestamp(),
            "readAt": NSNull(),
        ]
        try await Firestore.firestore()
            .collection("matches").document(matchId)
            .collection("messages")
            .addDocument(data: data)
    }
}

/// Toolbar/inline share affordance: presents the share sheet for `content`.
/// Must live under MainTabView's subtree (needs ChatStore in the environment).
struct ShareButton: View {
    let content: ShareableContent
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
        .sheet(isPresented: $isPresented) {
            ShareSheetView(content: content)
        }
    }
}

/// Share a profile/community/post/news card: send it to a match in-app
/// (drops a tappable link card into that chat) or hand the hosted link to
/// the system share sheet (WhatsApp, Messages, …).
struct ShareSheetView: View {
    let content: ShareableContent

    @Environment(SessionStore.self) private var session
    @Environment(ChatStore.self) private var chats
    @Environment(\.dismiss) private var dismiss

    @State private var sentMatchIds: Set<String> = []
    @State private var sendingMatchIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if chats.entries.isEmpty {
                        Text("Match with someone first to share inside Drokpo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chats.entries) { entry in
                            matchRow(entry)
                        }
                    }
                } header: {
                    Text("Send in a chat")
                }
                Section {
                    ShareLink(item: content.webURL, subject: Text(content.title), message: Text(content.title)) {
                        Label("Share via WhatsApp, Messages…", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Outside Drokpo")
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
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
        .presentationDetents([.medium, .large])
    }

    private func matchRow(_ entry: ChatStore.Entry) -> some View {
        HStack(spacing: 12) {
            RemotePhotoView(photo: entry.otherUser?.photos?.first)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            Text(entry.otherUser?.displayName ?? "—")
            Spacer()
            if sentMatchIds.contains(entry.matchId) {
                Label("Sent", systemImage: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            } else {
                Button("Send") {
                    Task { await send(to: entry) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(sendingMatchIds.contains(entry.matchId))
            }
        }
    }

    private func send(to entry: ChatStore.Entry) async {
        guard let uid = session.uid else { return }
        sendingMatchIds.insert(entry.matchId)
        defer { sendingMatchIds.remove(entry.matchId) }
        do {
            try await ChatMessageSender.sendText(content.messageText, matchId: entry.matchId, senderId: uid)
            sentMatchIds.insert(entry.matchId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
