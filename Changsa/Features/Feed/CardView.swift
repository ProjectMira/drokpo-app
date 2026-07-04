import SwiftUI

struct CardView: View {
    let card: FeedCard
    let onSafetyTapped: () -> Void

    @State private var photoIndex = 0

    private var photos: [Photo] { card.photos ?? [] }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RemotePhotoView(photo: photos.indices.contains(photoIndex) ? photos[photoIndex] : photos.first)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // Tap left/right half to flip through photos.
                if photos.count > 1 {
                    HStack(spacing: 0) {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { photoIndex = max(0, photoIndex - 1) }
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { photoIndex = min(photos.count - 1, photoIndex + 1) }
                    }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
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
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
