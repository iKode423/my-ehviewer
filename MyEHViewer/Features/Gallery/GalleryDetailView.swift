import SwiftUI

/// Displays a gallery detail page loaded from a search result.
struct GalleryDetailView: View {
    let result: EHSearchResult
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @StateObject private var siteCookieStore = SiteCookieStore.shared
    @StateObject private var imageCacheStore = ImageCacheStore.shared
    @StateObject private var downloadManager = GalleryDownloadManager.shared
    @StateObject private var viewModel: GalleryDetailViewModel
    @State private var showsMetadata = false

    /// Creates a detail view that loads the result's gallery URL.
    init(result: EHSearchResult) {
        self.result = result
        _viewModel = StateObject(wrappedValue: GalleryDetailViewModel(pageURL: result.pageURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.detail == nil {
                    GalleryLoadingView()
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
                    siteFavoriteStatus
                    metadataSection(for: detail)
                    tagsSection(for: detail)
                    pageLinksSection(for: detail)
                }
            }
            .padding()
        }
        .navigationTitle(AppCopy.galleryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            downloadButton
            favoriteMenu
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
            imageCacheStore.saveGalleryMetadata(detail: detail, fallback: result)
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
        CachedRemoteImageView(url: url, contentMode: .fill, animationMode: .staticPreview) {
            ProgressView()
        } failure: {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        .frame(width: 128, height: 176)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Shows parsed metadata rows from the gallery table.
    private func metadataSection(for detail: EHGalleryDetail) -> some View {
        DisclosureGroup(AppCopy.galleryMetadataTitle, isExpanded: $showsMetadata) {
            VStack(alignment: .leading, spacing: 10) {
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
            .padding(.top, 8)
        }
        .font(.headline)
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
                        .toolbar(.hidden, for: .tabBar)
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
                Text(galleryPagesTitle(for: detail))
                    .font(.headline)

                Spacer()

                if let startURL {
                    Button {
                        appNavigationStore.openReader(initialPageURL: startURL, pageLinks: detail.pageLinks, totalPageCount: detail.pageCount)
                    } label: {
                        Label(resumeURL == nil ? AppCopy.galleryReadFromStart : AppCopy.galleryContinueReading, systemImage: "book")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            downloadProgress(for: detail)

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

    /// Builds a page section title that uses the parsed gallery total when available.
    private func galleryPagesTitle(for detail: EHGalleryDetail) -> String {
        if let pageCount = detail.pageCount {
            return String(format: AppCopy.galleryPagesTitleFormat, String(pageCount))
        }
        return AppCopy.galleryPagesTitle
    }

    /// Shows cache/download progress for the current gallery.
    @ViewBuilder
    private func downloadProgress(for detail: EHGalleryDetail) -> some View {
        if let progress = downloadManager.progress(for: detail.identifier), progress.downloadedPageCount > 0 || progress.isRunning {
            Label(progress.displayText, systemImage: progress.isRunning ? "arrow.down.circle" : "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(progress.isRunning ? Color.secondary : Color.green)
        }
    }

    /// Shows one readable page thumbnail and opens it in the reader.
    private func pageLinkTile(_ pageLink: EHGalleryPageLink, allPageLinks: [EHGalleryPageLink]) -> some View {
        Button {
            appNavigationStore.openReader(initialPageURL: pageLink.pageURL, pageLinks: allPageLinks, totalPageCount: viewModel.detail?.pageCount)
        } label: {
            VStack(spacing: 6) {
                let thumbnail = pageThumbnailSource(for: pageLink)
                pageThumbnail(url: thumbnail.url, crop: thumbnail.crop)

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

    /// Picks the cached page image first, then falls back to the site thumbnail.
    private func pageThumbnailSource(for pageLink: EHGalleryPageLink) -> (url: URL?, crop: EHImageCrop?) {
        if let identifier = viewModel.detail?.identifier,
           let cachedURL = imageCacheStore.cachedImageURL(for: identifier, pageNumber: pageLink.pageNumber) {
            return (cachedURL, nil)
        }
        return (pageLink.thumbnailURL, pageLink.thumbnailCrop)
    }

    /// Shows a stable thumbnail frame for one reader page.
    private func pageThumbnail(url: URL?, crop: EHImageCrop?) -> some View {
        CachedRemoteImageView(url: url, crop: crop, contentMode: .fill, animationMode: .staticPreview) {
            ProgressView()
        } failure: {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.72, contentMode: .fit)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipped()
    }

    /// Shows local and site favorite actions from the toolbar.
    @ViewBuilder
    private var favoriteMenu: some View {
        if let detail = viewModel.detail {
            Menu {
                Button {
                    libraryStore.toggleFavorite(detail: detail, fallback: result)
                } label: {
                    Label(
                        libraryStore.isFavorite(detail.identifier) ? AppCopy.galleryLocalUnfavorite : AppCopy.galleryLocalFavorite,
                        systemImage: libraryStore.isFavorite(detail.identifier) ? "star.fill" : "star"
                    )
                }

                Button {
                    Task { await viewModel.addSiteFavorite() }
                } label: {
                    if viewModel.isUpdatingSiteFavorite {
                        Label(AppCopy.gallerySiteFavoriteSaving, systemImage: "hourglass")
                    } else {
                        Label(AppCopy.gallerySiteFavorite, systemImage: "icloud.and.arrow.up")
                    }
                }
                .disabled(!siteCookieStore.hasCookieHeader || viewModel.isUpdatingSiteFavorite)

                Button(role: .destructive) {
                    Task { await viewModel.removeSiteFavorite() }
                } label: {
                    Label(AppCopy.gallerySiteUnfavorite, systemImage: "icloud.slash")
                }
                .disabled(!siteCookieStore.hasCookieHeader || viewModel.isUpdatingSiteFavorite)

                if !siteCookieStore.hasCookieHeader {
                    Label(AppCopy.gallerySiteFavoriteRequiresCookie, systemImage: "key")
                }
            } label: {
                Label(AppCopy.galleryFavoriteMenu, systemImage: libraryStore.isFavorite(detail.identifier) ? "star.fill" : "star")
            }
        }
    }

    /// Shows the latest online favorite sync result.
    @ViewBuilder
    private var siteFavoriteStatus: some View {
        if let message = viewModel.siteFavoriteMessage {
            Label(message, systemImage: viewModel.siteFavoriteSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(viewModel.siteFavoriteSucceeded ? .green : .red)
        }
    }

    /// Starts a background cache download after loading all page links.
    private func startDownload(_ detail: EHGalleryDetail) async {
        if viewModel.canLoadMorePageLinks {
            await viewModel.loadAllPageLinks()
        }
        if let refreshedDetail = viewModel.detail {
            downloadManager.startDownload(detail: refreshedDetail, fallback: result)
        } else {
            downloadManager.startDownload(detail: detail, fallback: result)
        }
    }

    /// Shows the gallery download action.
    @ViewBuilder
    private var downloadButton: some View {
        if let detail = viewModel.detail {
            let progress = downloadManager.progress(for: detail.identifier)
            Button {
                Task { await startDownload(detail) }
            } label: {
                if progress?.isRunning == true {
                    Label(AppCopy.galleryDownloadQueued, systemImage: "arrow.down.circle")
                } else if let progress, progress.totalPageCount > 0, progress.downloadedPageCount >= progress.totalPageCount {
                    Label(AppCopy.galleryDownloadComplete, systemImage: "checkmark.circle")
                } else {
                    Label(AppCopy.galleryDownload, systemImage: "arrow.down.to.line")
                }
            }
            .disabled(progress?.isRunning == true || detail.pageLinks.isEmpty)
        }
    }
}

/// Shows an animated gallery loading placeholder that keeps layout stable.
private struct GalleryLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 52, height: 52)

                Circle()
                    .trim(from: 0.12, to: 0.82)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isAnimating && !reduceMotion ? 1.08 : 1.0)
            }

            Text(AppCopy.galleryLoadingTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                isAnimating = true
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
    .environmentObject(LibraryStore())
    .environmentObject(AppNavigationStore())
}
