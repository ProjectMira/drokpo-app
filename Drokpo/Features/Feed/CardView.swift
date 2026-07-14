import SwiftUI

struct CardView: View {
    let card: FeedCard
    let onSafetyTapped: () -> Void
    var onExpand: (() -> Void)? = nil

    @State private var photoIndex = 0

    private var photos: [Photo] { card.photos ?? [] }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RemotePhotoView(photo: photos.indices.contains(photoIndex) ? photos[photoIndex] : photos.first)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // Tap the outer thirds to flip through photos; the center
                // column expands the profile, same as tapping the info block.
                if photos.count > 1 {
                    HStack(spacing: 0) {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .frame(width: geometry.size.width * 0.3)
                            .onTapGesture { photoIndex = max(0, photoIndex - 1) }
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { onExpand?() }
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .frame(width: geometry.size.width * 0.3)
                            .onTapGesture { photoIndex = min(photos.count - 1, photoIndex + 1) }
                    }
                } else {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { onExpand?() }
                }

                // Fade reaches from mid-card past the info block to the
                // bottom, so the text and the deck's overlaid pass/like
                // buttons both sit on dark.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.40),
                        .init(color: .black.opacity(0.45), location: 0.62),
                        .init(color: .black.opacity(0.88), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    if photos.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(photos.indices, id: \.self) { index in
                                Capsule()
                                    .fill(index == photoIndex ? .white : .white.opacity(0.35))
                                    .frame(height: 3)
                            }
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(card.displayName ?? "—")
                            .font(.title.bold())
                        if let age = card.displayAge {
                            Text("\(age)").font(.title2)
                        }
                        if onExpand != nil {
                            Image(systemName: "chevron.up.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Button(action: onSafetyTapped) {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    if let region = card.region {
                        Label(region, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }
                    if let languages = card.languages, !languages.isEmpty {
                        Text(languages.joined(separator: " · "))
                            .font(.footnote)
                            .opacity(0.9)
                    }
                    if let bio = card.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.footnote)
                            .lineLimit(2)
                            .opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                // Keep the name/bio above the overlaid pass/like buttons.
                .padding(.bottom, SwipeActionButtons.deckClearance)
                .contentShape(Rectangle())
                .onTapGesture { onExpand?() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
