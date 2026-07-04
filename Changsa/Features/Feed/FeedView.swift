import SwiftUI

struct FeedView: View {
    @State private var model = FeedModel()

    var body: some View {
        NavigationStack {
            ZStack {
                if model.isLoading {
                    ProgressView()
                } else if model.cards.isEmpty {
                    emptyState
                } else {
                    deck
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.loadInitial() }
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
        }
    }

    private var deck: some View {
        VStack(spacing: 16) {
            ZStack {
                // Top 3 cards; the last in this array renders on top.
                ForEach(Array(model.cards.prefix(3).enumerated().reversed()), id: \.element.uid) { index, card in
                    SwipeableCard(
                        card: card,
                        isTop: index == 0,
                        onSwipe: { action in model.swipe(card, action: action) },
                        onReport: { reason in model.reportAndRemove(card, reason: reason) },
                        onBlock: { model.blockAndRemove(card) }
                    )
                    .scaleEffect(1 - CGFloat(index) * 0.03)
                    .offset(y: CGFloat(index) * 10)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 40) {
                actionButton(systemImage: "xmark", tint: .red) {
                    if let top = model.cards.first { model.swipe(top, action: .pass) }
                }
                actionButton(systemImage: "heart.fill", tint: .green) {
                    if let top = model.cards.first { model.swipe(top, action: .like) }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func actionButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .frame(width: 60, height: 60)
                .background(Circle().fill(.background).shadow(radius: 4))
                .foregroundStyle(tint)
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

private struct SwipeableCard: View {
    let card: FeedCard
    let isTop: Bool
    let onSwipe: (SwipeAction) -> Void
    let onReport: (String) -> Void
    let onBlock: () -> Void

    @State private var offset: CGSize = .zero
    @State private var showSafetySheet = false
    @State private var showReportReasons = false

    private let swipeThreshold: CGFloat = 110

    var body: some View {
        CardView(card: card) { showSafetySheet = true }
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 18)))
            .overlay(alignment: .topLeading) { stamp("LIKE", color: .green, visible: offset.width > 40) }
            .overlay(alignment: .topTrailing) { stamp("PASS", color: .red, visible: offset.width < -40) }
            .gesture(isTop ? dragGesture : nil)
            .animation(.spring(duration: 0.3), value: offset)
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

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                if value.translation.width > swipeThreshold {
                    offset = CGSize(width: 600, height: value.translation.height)
                    onSwipe(.like)
                } else if value.translation.width < -swipeThreshold {
                    offset = CGSize(width: -600, height: value.translation.height)
                    onSwipe(.pass)
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
            .rotationEffect(.degrees(text == "LIKE" ? -15 : 15))
            .opacity(visible ? 1 : 0)
            .padding(24)
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
