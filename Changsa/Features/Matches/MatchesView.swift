import SwiftUI

struct MatchesView: View {
    @State private var matches: [Match] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if matches.isEmpty {
                    emptyState
                } else {
                    matchList
                }
            }
            .navigationTitle("Matches")
            .task { await load() }
            .refreshable { await load() }
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

    private var matchList: some View {
        List {
            ForEach(matches) { match in
                NavigationLink {
                    MatchDetailView(match: match)
                } label: {
                    HStack(spacing: 12) {
                        RemotePhotoView(photo: match.otherUser?.photos?.first)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(match.otherUser?.displayName ?? "—")
                                .font(.headline)
                            if let region = match.otherUser?.region {
                                Text(region)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .swipeActions {
                    Button("Unmatch", role: .destructive) {
                        Task { await unmatch(match) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No matches yet")
                .font(.headline)
            Text("When you and someone else like each other, they'll show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func load() async {
        do {
            let list: TolerantList<Match> = try await APIClient.shared.get("/api/matches")
            matches = list.items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func unmatch(_ match: Match) async {
        guard let matchId = match.matchId else { return }
        matches.removeAll { $0.id == match.id }
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/matches/\(matchId)/unmatch")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shows the matched person's profile. Becomes the chat entry point once the
/// backend ships message endpoints.
struct MatchDetailView: View {
    let match: Match

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photos = match.otherUser?.photos, !photos.isEmpty {
                    TabView {
                        ForEach(photos) { photo in
                            RemotePhotoView(photo: photo)
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(match.otherUser?.displayName ?? "—")
                            .font(.title.bold())
                        if let age = match.otherUser?.displayAge {
                            Text("\(age)").font(.title2)
                        }
                    }
                    if let region = match.otherUser?.region {
                        Label(region, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                    if let languages = match.otherUser?.languages, !languages.isEmpty {
                        Label(languages.joined(separator: ", "), systemImage: "globe")
                            .foregroundStyle(.secondary)
                    }
                    if let bio = match.otherUser?.bio, !bio.isEmpty {
                        Text(bio).padding(.top, 4)
                    }
                }

                Label("Chat is coming soon", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
            }
            .padding()
        }
        .navigationTitle(match.otherUser?.displayName ?? "Match")
        .navigationBarTitleDisplayMode(.inline)
    }
}
