import SwiftUI

/// Displays a gallery detail page loaded from a search result.
struct GalleryDetailView: View {
    let result: EHSearchResult
    @StateObject private var viewModel: GalleryDetailViewModel

    /// Creates a detail view that loads the result's gallery URL.
    init(result: EHSearchResult) {
        self.result = result
        _viewModel = StateObject(wrappedValue: GalleryDetailViewModel(pageURL: result.pageURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.detail == nil {
                    ContentUnavailableView(AppCopy.galleryLoadingTitle, systemImage: "hourglass")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if let errorMessage = viewModel.errorMessage, viewModel.detail == nil {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if let detail = viewModel.detail {
                    header(for: detail)
                    metadataSection(for: detail)
                    tagsSection(for: detail)
                    pageLinksSection(for: detail)
                }
            }
            .padding()
        }
        .navigationTitle(AppCopy.galleryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    /// Shows cover art and primary gallery metadata.
    private func header(for detail: EHGalleryDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            coverImage(url: detail.coverURL ?? result.thumbnailURL)

            VStack(alignment: .leading, spacing: 10) {
                Text(detail.title)
                    .font(.title3.weight(.semibold))

                if let japaneseTitle = detail.japaneseTitle {
                    Text(japaneseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(EHGalleryCategory.displayName(forSiteLabel: detail.category))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let uploader = detail.uploader {
                    Label(uploader, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let ratingLabel = detail.ratingLabel {
                    Label(ratingLabel, systemImage: "star")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Shows a stable cover image frame.
    private func coverImage(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            case .empty:
                ProgressView()
            @unknown default:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 128, height: 176)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Shows parsed metadata rows from the gallery table.
    private func metadataSection(for detail: EHGalleryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppCopy.galleryMetadataTitle)
                .font(.headline)

            ForEach(detail.metadata) { item in
                HStack(alignment: .top) {
                    Text(item.key)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Text(item.value)
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
    }

    /// Shows a wrapping list of parsed gallery tags.
    private func tagsSection(for detail: EHGalleryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppCopy.galleryTagsTitle)
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(detail.tags) { tag in
                    Text(tag.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }

    /// Shows reader page links parsed from the thumbnail grid.
    private func pageLinksSection(for detail: EHGalleryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppCopy.galleryPagesTitle)
                    .font(.headline)

                Spacer()

                if let firstPage = detail.pageLinks.first {
                    NavigationLink {
                        ReaderView(initialPageURL: firstPage.pageURL)
                    } label: {
                        Label(AppCopy.galleryReadFromStart, systemImage: "book")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if detail.pageLinks.isEmpty {
                Text(AppCopy.galleryNoPages)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(detail.pageLinks) { pageLink in
                        NavigationLink {
                            ReaderView(initialPageURL: pageLink.pageURL)
                        } label: {
                            Text(String(format: AppCopy.galleryOpenPage, String(pageLink.pageNumber)))
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GalleryDetailView(
            result: EHSearchResult(
                identifier: EHGalleryIdentifier(gid: 100, token: "abcdef1234"),
                title: "Sample Gallery",
                category: "Manga",
                pageURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!,
                thumbnailURL: nil,
                uploader: "demo",
                postedText: nil,
                pageCountText: "2 pages",
                tags: []
            )
        )
    }
}
