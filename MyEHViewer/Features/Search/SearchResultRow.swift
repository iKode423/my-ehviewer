import SwiftUI

/// Renders one gallery result in the search list.
struct SearchResultRow: View {
    let result: EHSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(EHGalleryCategory.displayName(forSiteLabel: result.category))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let pageCountText = localizedPageCount {
                        Text(pageCountText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(result.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(3)

                if let uploader = result.uploader, !uploader.isEmpty {
                    Label(uploader, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                tagStrip
            }
        }
        .padding(.vertical, 6)
    }

    /// Shows the remote thumbnail with a stable frame.
    private var thumbnail: some View {
        AsyncImage(url: result.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            case .empty:
                ProgressView()
            @unknown default:
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 96)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Shows a short strip of tags without crowding the row.
    @ViewBuilder
    private var tagStrip: some View {
        if !result.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(result.tags.prefix(4)) { tag in
                        Text(tag.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
        }
    }

    /// Converts common English page-count text from the site into Chinese.
    private var localizedPageCount: String? {
        guard let pageCountText = result.pageCountText else { return nil }
        return pageCountText
            .replacingOccurrences(of: " pages", with: " 页")
            .replacingOccurrences(of: " page", with: " 页")
    }
}

#Preview {
    SearchResultRow(
        result: EHSearchResult(
            identifier: EHGalleryIdentifier(gid: 100, token: "abcdef1234"),
            title: "Sample Gallery",
            category: "漫画",
            pageURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!,
            thumbnailURL: nil,
            uploader: "demo",
            postedText: "2026-07-05",
            pageCountText: "12 pages",
            tags: [EHTag(namespace: "artist", name: "sample")]
        )
    )
}
