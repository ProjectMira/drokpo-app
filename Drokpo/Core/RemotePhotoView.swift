import SwiftUI

/// Renders a profile photo. Uses the photo's URL when the backend provides one,
/// otherwise resolves a download URL from its Firebase Storage path.
///
/// Loads image data manually instead of via AsyncImage: AsyncImage reports a
/// cancelled load — routine when cells re-layout inside a List/ScrollView — as
/// `.failure` and never retries, which left perfectly valid photos stuck on an
/// error icon.
struct RemotePhotoView: View {
    let photo: Photo?

    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    @State private var phase: Phase = .loading

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            switch phase {
            case .loaded(let image):
                Image(uiImage: image).resizable().scaledToFill()
            case .failed:
                placeholder(icon: "photo.badge.exclamationmark")
                    .onTapGesture {
                        Task { await load() }
                    }
            case .loading:
                placeholder(icon: photo == nil ? "person.fill" : nil)
            }
        }
        .task(id: photo?.storagePath) { await load() }
    }

    private func load() async {
        guard let photo else { return }
        if let cached = Self.cache.object(forKey: photo.storagePath as NSString) {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        // Two attempts smooth over transient network blips. Cancellation (the
        // view scrolled away) is not a failure — the next .task retries fresh.
        for attempt in 0..<2 {
            do {
                let url: URL
                if let provided = photo.url.flatMap(URL.init(string:)) {
                    url = provided
                } else {
                    url = try await PhotoUploader.downloadURL(for: photo.storagePath)
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let image = UIImage(data: data) else {
                    throw URLError(.badServerResponse)
                }
                Self.cache.setObject(image, forKey: photo.storagePath as NSString)
                phase = .loaded(image)
                return
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        phase = .failed
    }

    @ViewBuilder
    private func placeholder(icon: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let icon {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }
}

/// A fixed-aspect image band whose photo can never affect surrounding layout.
///
/// RemotePhotoView renders its image with `scaledToFill`, which overflows its
/// proposed bounds; unclipped, that overflow inflates the layout around it
/// (it once pushed the whole news detail sheet wider than the screen). This
/// container owns the geometry — the band is always `aspect` at the offered
/// width — and clips the photo to it.
struct PhotoBand: View {
    let photo: Photo?
    var aspect: CGFloat = 16 / 9

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { RemotePhotoView(photo: photo) }
            .clipped()
    }
}
