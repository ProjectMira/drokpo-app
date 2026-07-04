import SwiftUI

/// Renders a profile photo. Uses the photo's URL when the backend provides one,
/// otherwise resolves a download URL from its Firebase Storage path.
struct RemotePhotoView: View {
    let photo: Photo?

    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(icon: "photo.badge.exclamationmark")
                    default:
                        placeholder(icon: nil)
                    }
                }
            } else {
                placeholder(icon: photo == nil ? "person.fill" : nil)
            }
        }
        .task(id: photo?.storagePath) {
            guard let photo else { return }
            if let url = photo.url.flatMap(URL.init(string:)) {
                resolvedURL = url
            } else {
                resolvedURL = try? await PhotoUploader.downloadURL(for: photo.storagePath)
            }
        }
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
