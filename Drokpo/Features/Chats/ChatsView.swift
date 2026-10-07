import SwiftUI

struct ChatsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ChatStore.self) private var chats
    @State private var router = DeepLinkRouter.shared
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if chats.isLoading && chats.entries.isEmpty {
                    ProgressView()
                } else if chats.entries.isEmpty {
                    emptyState
                } else {
                    chatList
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: String.self) { matchId in
                ChatThreadView(matchId: matchId)
            }
            .alert("Something went wrong", isPresented: .init(
                get: { chats.errorMessage != nil },
                set: { if !$0 { chats.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(chats.errorMessage ?? "")
            }
        }
        .onAppear { consumeDeepLink() }
        .onChange(of: router.pendingMatchId) { consumeDeepLink() }
    }

    /// A "message" push opens the thread; a "match" push just lands on the list.
    /// Pushing before entries load is fine — ChatThreadView looks the match up
    /// by id once the ChatStore listener delivers it.
    private func consumeDeepLink() {
        guard router.pendingMatchId != nil || router.pendingType != nil else { return }
        if router.pendingType == "message", let matchId = router.pendingMatchId {
            path = [matchId]
        }
        router.clear()
    }

    private var chatList: some View {
        List {
            if !chats.newMatches.isEmpty {
                Section("New matches") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(chats.newMatches) { entry in
                                NavigationLink(value: entry.matchId) {
                                    VStack(spacing: 6) {
                                        RemotePhotoView(photo: entry.otherUser?.photos?.first)
                                            .frame(width: 64, height: 64)
                                            .clipShape(Circle())
                                        Text(entry.otherUser?.displayName ?? "—")
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 72)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                ForEach(chats.conversations) { entry in
                    NavigationLink(value: entry.matchId) {
                        conversationRow(entry)
                    }
                    .swipeActions {
                        Button("Unmatch", role: .destructive) {
                            Task { await unmatch(entry) }
                        }
                    }
                }
            }
        }
    }

    private func conversationRow(_ entry: ChatStore.Entry) -> some View {
        HStack(spacing: 12) {
            RemotePhotoView(photo: entry.otherUser?.photos?.first)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.otherUser?.displayName ?? "—")
                    .font(.headline)
                if let text = entry.lastMessageText {
                    Text(entry.lastMessageSenderId == session.uid ? "You: \(text)" : text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if entry.unread > 0 {
                Text("\(entry.unread)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Circle().fill(.tint))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No chats yet")
                .font(.headline)
            Text("When you and someone else like each other, you can start chatting here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                router.select(.discover)
            } label: {
                Label("Discover people", systemImage: "rectangle.stack.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func unmatch(_ entry: ChatStore.Entry) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/matches/\(entry.matchId)/unmatch")
            // The Firestore listener drops the match automatically once its
            // status flips to "unmatched".
        } catch {
            chats.errorMessage = error.localizedDescription
        }
    }
}
