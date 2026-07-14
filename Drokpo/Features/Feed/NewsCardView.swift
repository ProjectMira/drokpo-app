import SwiftUI

/// A news card in the Discover deck. News share images are almost always
/// landscape, so instead of force-cropping them full-bleed the card shows the
/// photo as a full-width 16:9 band on a dark backdrop, with a fade rising
/// from the bottom that carries the text — and, above the reserved clearance,
/// the deck's overlaid pass/like buttons — in clear contrast.
struct NewsCardView: View {
    let item: NewsCard
    /// Open the source article in the in-app browser; nil when not the top card.
    var onOpen: (() -> Void)? = nil
    /// Show the full-summary detail sheet; nil when not the top card.
    var onExpand: (() -> Void)? = nil

    private var photos: [Photo] { item.displayPhotos }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Dark backdrop lets a landscape photo letterbox cleanly; the
                // brand gradient fills in when the story has no image at all.
                if photos.first == nil {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.85), .brandRed.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color(white: 0.07)
                }

                if let photo = photos.first {
                    VStack(spacing: 0) {
                        PhotoBand(photo: photo)
                            .frame(width: geometry.size.width)
                            .padding(.top, 52) // clear of the badge / arrow row
                        Spacer(minLength: 0)
                    }
                }

                // The fade reaches from mid-card down past the text to the
                // buttons, so everything written sits on dark.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: .black.opacity(0.55), location: 0.55),
                        .init(color: .black.opacity(0.94), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if let sourceName = item.sourceName, !sourceName.isEmpty {
                            Text(sourceName.uppercased())
                                .font(.caption.bold())
                                .opacity(0.85)
                        }
                        if let relative = item.relativePublished {
                            Text("· \(relative)")
                                .font(.caption)
                                .opacity(0.7)
                        }
                    }
                    Text(item.title ?? "—")
                        .font(.title2.bold())
                        .lineLimit(3)
                    if let gist = item.gist, !gist.isEmpty {
                        Text(gist)
                            .font(.subheadline)
                            .lineLimit(3)
                            .opacity(0.95)
                    }
                    if onOpen != nil {
                        Label("Swipe right to save · arrow to read", systemImage: "hand.draw")
                            .font(.caption.bold())
                            .opacity(0.8)
                            .padding(.top, 2)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                // Keep every word above the overlaid pass/like buttons.
                .padding(.bottom, SwipeActionButtons.deckClearance)
            }
            .overlay(alignment: .topLeading) {
                Text("News")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                // Explicit "open the source" affordance — a Button so it wins
                // over the card's tap-to-expand gesture.
                if onOpen != nil {
                    Button {
                        onOpen?()
                    } label: {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Whole card (photo, chevron, text) expands the detail sheet;
            // the arrow Button keeps priority over this ancestor gesture.
            .contentShape(Rectangle())
            .onTapGesture { onExpand?() }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
