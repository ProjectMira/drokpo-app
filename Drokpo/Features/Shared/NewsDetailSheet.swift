import SwiftUI

/// Tap-through detail for a news card: full summary, source attribution, and
/// a button to open the source article in the in-app browser. Used as a sheet
/// from the Discover deck; ShareDestinationView reuses NewsDetailContent for
/// stories arriving via share links.
struct NewsDetailSheet: View {
    let item: NewsCard
    let onReadFullStory: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                NewsDetailContent(item: item, onReadFullStory: onReadFullStory)
            }
            .navigationTitle("News")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareButton(content: .news(item))
                }
            }
        }
    }
}

/// The scrollable body of a news story's detail view. The image is a
/// PhotoBand — a fixed-aspect, clipped container — because an unclipped
/// scaled-to-fill photo once inflated the whole sheet wider than the screen.
struct NewsDetailContent: View {
    let item: NewsCard
    let onReadFullStory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let photo = item.displayPhotos.first {
                PhotoBand(photo: photo)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 6) {
                if let sourceName = item.sourceName, !sourceName.isEmpty {
                    Text(sourceName.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                if let relative = item.relativePublished {
                    Text("· \(relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(item.title ?? "—")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(item.summary?.isEmpty == false ? item.summary! : item.gist ?? "")
                .font(.body)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onReadFullStory()
            } label: {
                Text("Read the full story")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
