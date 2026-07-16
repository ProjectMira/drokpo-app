import SwiftUI

/// Determines the bottom action bar and CTA behavior for `ProfileDetailView`,
/// so the same view serves the Likes list, Discover's expanded card, and
/// plain read-only views (own profile preview, matched-chat header).
enum ProfileDetailContext {
    case plain
    /// Viewing a "Liked you" entry that isn't a match yet — offers "Like
    /// back", which flips to "Send message" in place once it matches.
    case likedYou(onLikeBack: () async -> SwipeResult?)
    /// Viewing an expanded card from the Discover deck.
    case discover(onLike: () -> Void, onPass: () -> Void)
}

/// Full-screen look at another member's profile, pushed from the chats and
/// likes lists, or presented as a sheet from Discover.
struct ProfileDetailView: View {
    let card: FeedCard
    var context: ProfileDetailContext = .plain
    /// Caller-owned report/block — Discover passes these so the card also
    /// leaves the deck. When nil, the view calls the safety APIs itself
    /// (Likes list, chat header, shared links).
    var onReport: ((String) -> Void)? = nil
    var onBlock: (() -> Void)? = nil

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var localMatchId: String?
    @State private var isLiking = false
    @State private var showMatchAlert = false
    @State private var showBlockConfirm = false
    @State private var showReportReasons = false
    @State private var errorMessage: String?

    /// Own-profile preview (ProfileView) — no reporting/blocking yourself.
    private var isSelf: Bool {
        card.uid == session.uid || card.uid == "me"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photos = card.photos, !photos.isEmpty {
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
                        Text(card.displayName ?? "—")
                            .font(.title.bold())
                        if let age = card.displayAge {
                            Text("\(age)").font(.title2)
                        }
                    }
                    if let region = card.region {
                        Label(region, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                    if let distanceKm = card.distanceKm {
                        Label("~\(Int(distanceKm.rounded())) km away", systemImage: "location.fill")
                            .foregroundStyle(.secondary)
                    }
                    if let occupation = card.occupation, !occupation.isEmpty {
                        Label(occupation, systemImage: "briefcase.fill")
                            .foregroundStyle(.secondary)
                    }
                    if let education = card.education, !education.isEmpty {
                        Label(education, systemImage: "graduationcap.fill")
                            .foregroundStyle(.secondary)
                    }
                    if let languages = card.languages, !languages.isEmpty {
                        Label(languages.joined(separator: ", "), systemImage: "globe")
                            .foregroundStyle(.secondary)
                    }
                    if let instagram = card.socials?.instagram, !instagram.isEmpty {
                        Label("@\(instagram)", systemImage: "camera")
                            .foregroundStyle(.secondary)
                    }
                    if let bio = card.bio, !bio.isEmpty {
                        Text(bio).padding(.top, 4)
                    }
                    if let interests = card.interests, !interests.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Interests", systemImage: "sparkles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 8) {
                                ForEach(interests, id: \.self) { interest in
                                    Text(interest)
                                        .font(.footnote)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(.quaternary))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    if !answeredQuestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(answeredQuestions, id: \.question.id) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.question.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.answer)
                                        .font(.body)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding()
            .padding(.bottom, hasActionBar ? 72 : 0)
        }
        .navigationTitle(card.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareButton(
                    content: card.isCommunity
                        ? .community(cid: card.uid, name: card.displayName)
                        : .profile(card)
                )
            }
            if !isSelf {
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
            "Why are you reporting this profile?",
            isPresented: $showReportReasons,
            titleVisibility: .visible
        ) {
            ForEach(Vocabulary.reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) { report(reason: reason) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Block \(card.displayName ?? "this member")?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { block() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see each other anywhere in Drokpo.")
        }
        .alert("It's a match!", isPresented: $showMatchAlert) {
            Button("Say hi") { openThread() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("You and \(card.displayName ?? "they") liked each other.")
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

    /// Report through the caller when it owns cleanup (Discover removes the
    /// card from the deck); otherwise call the API directly.
    private func report(reason: String) {
        if let onReport {
            onReport(reason)
            return
        }
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/reports",
                    body: ReportIn(reportedUid: card.uid, reason: reason, note: "")
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func block() {
        if let onBlock {
            onBlock()
            return
        }
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(card.uid)")
                BlockStore.shared.record(uid: card.uid, displayName: card.displayName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The profile's prompt answers, in the vocabulary's order. Only known
    /// question keys are shown, so retired questions vanish gracefully.
    private var answeredQuestions: [(question: ProfileQuestion, answer: String)] {
        Vocabulary.questions.compactMap { question in
            guard let answer = card.answers?[question.key],
                  !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (question, answer)
        }
    }

    private var hasActionBar: Bool {
        if case .plain = context { return false }
        return true
    }

    @ViewBuilder
    private var actionBar: some View {
        switch context {
        case .plain:
            EmptyView()
        case .likedYou(let onLikeBack):
            Group {
                if let activeMatchId = localMatchId {
                    Button {
                        openThread(matchId: activeMatchId)
                    } label: {
                        Label("Send message", systemImage: "bubble.left.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        Task { await likeBack(onLikeBack) }
                    } label: {
                        Label("Like back", systemImage: "heart.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.brandRed)
                    .disabled(isLiking)
                }
            }
            .padding()
            .background(.bar)
        case .discover(let onLike, let onPass):
            SwipeActionButtons(onPass: onPass, onLike: onLike)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    private func likeBack(_ onLikeBack: () async -> SwipeResult?) async {
        isLiking = true
        defer { isLiking = false }
        guard let result = await onLikeBack(), result.isMatch else { return }
        localMatchId = result.matchId ?? result.match?.matchId
        showMatchAlert = true
    }

    private func openThread(matchId: String? = nil) {
        guard let matchId = matchId ?? localMatchId else { return }
        DeepLinkRouter.shared.handle(type: "message", matchId: matchId)
    }
}
