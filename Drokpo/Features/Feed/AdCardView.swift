import SwiftUI

/// A sponsored card in the Discover deck — same banded layout as the other
/// content cards (ad creatives are typically landscape): photo band on a
/// dark backdrop, bottom fade carrying the pitch and CTA above the deck's
/// overlaid buttons, clearly labelled.
struct AdCardView: View {
    let ad: AdCard
    /// Open the ad link (same as swiping right); nil when not the top card.
    var onOpen: (() -> Void)? = nil

    private var photos: [Photo] { ad.displayPhotos }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
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
                            .padding(.top, 52) // clear of the Sponsored badge
                        Spacer(minLength: 0)
                    }
                }

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
                    Text(ad.title ?? "—")
                        .font(.title2.bold())
                        .lineLimit(3)
                    if let body = ad.body, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .lineLimit(3)
                            .opacity(0.95)
                    }
                    if onOpen != nil {
                        Button {
                            onOpen?()
                        } label: {
                            Text(ad.ctaLabel?.isEmpty == false ? ad.ctaLabel! : "Learn more")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                // Keep the pitch and CTA above the overlaid pass/like buttons.
                .padding(.bottom, SwipeActionButtons.deckClearance)
            }
            .overlay(alignment: .topLeading) {
                Text("Sponsored")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
