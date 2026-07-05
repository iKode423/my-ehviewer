import SwiftUI

/// Displays a gallery detail page loaded from a search result.
struct GalleryDetailView: View {
    let result: EHSearchResult
    @EnvironmentObject private var libraryStore: LibraryStore
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
                    VStack(spacing: 16) {
                        ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")

                        Button {
                            Task {
                                await viewModel.reload()
                                recordLoadedDetail()
                            }
                        } label: {
                            Label(AppCopy.commonRetry, systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoading)
                    }
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
        .toolbar {
            if let detail = viewModel.detail {
                Button {
                    libraryStore.toggleFavorite(detail: detail, fallback: result)
                } label: {
                    Label(
                        libraryStore.isFavorite(detail.identifier) ? AppCopy.libraryUnfavoriteAction : AppCopy.libraryFavoriteAction,
                        systemImage: libraryStore.isFavorite(detail.identifier) ? "star.fill" : "star"
                    )
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            recordLoadedDetail()
        }
        .refreshable {
            await viewModel.reload()
            recordLoadedDetail()
        }
    }

    /// Records a loaded detail page into local history.
    private func recordLoadedDetail() {
        if let detail = viewModel.detail {
            libraryStore.record(detail: detail, fallback: result)
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
        return VStack(alignment: .leading, spacing: 10) {
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
        return VStack(alignment: .leading, spacing: 10) {
            Text(AppCopy.galleryTagsTitle)
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(detail.tags) { tag in
                    NavigationLink {
                        SearchView(
                            viewModel: SearchViewModel(initialQuery: tag.searchQuery),
                            embedsInNavigationStack: false,
                            searchesOnAppear: true
                        )
                    } label: {
                        Label {
                            Text(tag.displayName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 220)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Shows reader page links parsed from the thumbnail grid.
    private func pageLinksSection(for detail: EHGalleryDetail) -> some View {
        let resumeURL = libraryStore.record(for: detail.identifier)?.lastReadPageURL
        let startURL = resumeURL ?? detail.pageLinks.first?.pageURL

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppCopy.galleryPagesTitle)
                    .font(.headline)

                Spacer()

                if let startURL {
                    NavigationLink {
                        ReaderView(initialPageURL: startURL, pageLinks: detail.pageLinks)
                    } label: {
                        Label(resumeURL == nil ? AppCopy.galleryReadFromStart : AppCopy.galleryContinueReading, systemImage: "book")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if detail.pageLinks.isEmpty {
                Text(AppCopy.galleryNoPages)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(detail.pageLinks) { pageLink in
                        pageLinkTile(pageLink, allPageLinks: detail.pageLinks)
                    }
                }

                if viewModel.canLoadMorePageLinks {
                    HStack {
                        Button {
                            Task { await viewModel.loadMorePageLinks() }
                        } label: {
                            if viewModel.isLoadingMorePageLinks {
                                Label(AppCopy.galleryLoadingMorePages, systemImage: "hourglass")
                            } else {
                                Label(AppCopy.galleryLoadMorePages, systemImage: "rectangle.stack.badge.plus")
                            }
                        }
                        .disabled(viewModel.isLoadingMorePageLinks || viewModel.isLoadingAllPageLinks)

                        Button {
                            Task { await viewModel.loadAllPageLinks() }
                        } label: {
                            if viewModel.isLoadingAllPageLinks {
                                Label(AppCopy.galleryLoadingAllPages, systemImage: "hourglass")
                            } else {
                                Label(AppCopy.galleryLoadAllPages, systemImage: "square.stack.3d.up")
                            }
                        }
                        .disabled(viewModel.isLoadingMorePageLinks || viewModel.isLoadingAllPageLinks)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// Shows one readable page thumbnail and opens it in the reader.
    private func pageLinkTile(_ pageLink: EHGalleryPageLink, allPageLinks: [EHGalleryPageLink]) -> some View {
        NavigationLink {
            ReaderView(initialPageURL: pageLink.pageURL, pageLinks: allPageLinks)
        } label: {
            VStack(spacing: 6) {
                pageThumbnail(url: pageLink.thumbnailURL)

                Text(String(format: AppCopy.galleryOpenPage, String(pageLink.pageNumber)))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Shows a stable thumbnail frame for one reader page.
    private func pageThumbnail(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            case .empty:
                ProgressView()
            @unknown default:
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.72, contentMode: .fit)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipped()
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
    .environmentObject(LibraryStore())
}
