import SwiftUI
import UIKit

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
    @State private var showsTags = false

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

                        if let summary = cachedSummary {
                            cachedPageLinksSection(for: summary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else if let detail = viewModel.detail {
                    header(for: detail)
                    siteFavoriteStatus
                    metadataSection(for: detail)
                    tagsSection(for: detail)
                    pageLinksSection(for: detail)
                    relatedGalleriesSection(for: detail)
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
            await refreshSiteFavoriteStatusIfNeeded()
        }
        .refreshable {
            await viewModel.reload()
            recordLoadedDetail()
            await refreshSiteFavoriteStatusIfNeeded()
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
            coverImage(url: detail.coverURL ?? result.thumbnailURL, referer: result.pageURL)

            VStack(alignment: .leading, spacing: 10) {
                galleryTitleLabel(detail.title)

                if let japaneseTitle = detail.japaneseTitle {
                    Text(japaneseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(EHGalleryCategory.displayName(forSiteLabel: detail.category))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                siteFavoriteBadge

                if let uploader = detail.uploader {
                    uploaderLabel(uploader)
                }

                if let ratingLabel = detail.ratingLabel {
                    Label(ratingLabel, systemImage: "star")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Refreshes online favorite state only when the user has configured site cookies.
    private func refreshSiteFavoriteStatusIfNeeded() async {
        guard siteCookieStore.hasCookieHeader, viewModel.detail?.identifier.site.supportsOnlineFavorites == true else { return }
        await viewModel.refreshSiteFavoriteStatus()
    }

    /// Shows a stable cover image frame.
    private func coverImage(url: URL?, referer: URL?) -> some View {
        CachedRemoteImageView(url: url, referer: referer, contentMode: .fill, animationMode: .staticPreview, decodeMaxPixelSize: 560) {
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

    /// Shows the gallery title and offers a long-press copy action.
    private func galleryTitleLabel(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .textSelection(.enabled)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = title
                } label: {
                    Label(AppCopy.commonCopy, systemImage: "doc.on.doc")
                }
            }
    }

    /// Shows the author/uploader name and offers a long-press copy action.
    private func uploaderLabel(_ uploader: String) -> some View {
        Label(uploader, systemImage: "person")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = uploader
                } label: {
                    Label(AppCopy.commonCopy, systemImage: "doc.on.doc")
                }
            }
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
                        metadataValue(for: item, site: detail.identifier.site)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
    }

    /// Shows metadata text or direct search links for structured values.
    @ViewBuilder
    private func metadataValue(for item: EHMetadataItem, site: ContentSite) -> some View {
        if item.searchTags.isEmpty {
            Text(item.value)
                .multilineTextAlignment(.trailing)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(item.searchTags) { tag in
                    NavigationLink {
                        searchView(for: tag, site: site)
                    } label: {
                        Label(tag.name, systemImage: "magnifyingglass")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: 220, alignment: .trailing)
        }
    }

    /// Shows a wrapping list of parsed gallery tags.
    private func tagsSection(for detail: EHGalleryDetail) -> some View {
        DisclosureGroup(AppCopy.galleryTagsTitle, isExpanded: $showsTags) {
            FlowLayout(spacing: 8) {
                ForEach(detail.tags) { tag in
                    NavigationLink {
                        searchView(for: tag, site: detail.identifier.site)
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
            .padding(.top, 8)
        }
        .font(.headline)
    }

    /// Builds a search screen pinned to the gallery's source site.
    private func searchView(for tag: EHTag, site: ContentSite) -> some View {
        SearchView(
            viewModel: SearchViewModel(initialQuery: tag.searchQuery, initialSite: site),
            embedsInNavigationStack: false,
            searchesOnAppear: true,
            followsAppContentSite: false
        )
        .toolbar(.hidden, for: .tabBar)
    }

    /// Shows reader page links parsed from the thumbnail grid.
    private func pageLinksSection(for detail: EHGalleryDetail) -> some View {
        let libraryRecord = libraryStore.record(for: detail.identifier)
        let resumeURL = libraryRecord?.lastReadPageURL
        let startURL = resumeURL ?? detail.pageLinks.first?.pageURL
        let readButtonTitle = galleryReadButtonTitle(resumePage: libraryRecord?.lastReadPage, hasResume: resumeURL != nil)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(galleryPagesTitle(for: detail))
                    .font(.headline)

                Spacer()

                if let startURL {
                    Button {
                        appNavigationStore.openReader(initialPageURL: startURL, pageLinks: detail.pageLinks, totalPageCount: detail.pageCount)
                    } label: {
                        Label(readButtonTitle, systemImage: "book")
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
                        pageLinkTile(
                            pageLink,
                            allPageLinks: detail.pageLinks,
                            galleryIdentifier: detail.identifier,
                            totalPageCount: detail.pageCount
                        )
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

    /// Shows Hitomi-related galleries under the preview grid.
    @ViewBuilder
    private func relatedGalleriesSection(for detail: EHGalleryDetail) -> some View {
        if !detail.relatedGalleries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(AppCopy.galleryRelatedTitle)
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach(detail.relatedGalleries) { result in
                    NavigationLink {
                        GalleryDetailView(result: result)
                    } label: {
                        SearchResultRow(result: result)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if result.id != detail.relatedGalleries.last?.id {
                        Divider()
                            .padding(.leading, 84)
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shows locally cached pages when the live gallery page cannot be loaded.
    private func cachedPageLinksSection(for summary: CachedGallerySummary) -> some View {
        let pageLinks = cachedPageLinks(for: summary)
        let resumeURL = libraryStore.record(for: summary.galleryIdentifier)?.lastReadPageURL
        let resumePage = libraryStore.record(for: summary.galleryIdentifier)?.lastReadPage
        let cachedPageURLs = Set(pageLinks.map(\.pageURL))
        let cachedResumeURL = resumeURL.flatMap { cachedPageURLs.contains($0) ? $0 : nil }
        let startURL = cachedResumeURL ?? pageLinks.first?.pageURL
        let readButtonTitle = galleryReadButtonTitle(resumePage: resumePage, hasResume: cachedResumeURL != nil)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppCopy.galleryCachedPagesTitle)
                        .font(.headline)
                    Text(AppCopy.galleryCachedPagesMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let startURL {
                    Button {
                        appNavigationStore.openReader(
                            initialPageURL: startURL,
                            pageLinks: pageLinks,
                            totalPageCount: summary.totalPageCount
                        )
                    } label: {
                        Label(readButtonTitle, systemImage: "book")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(pageLinks) { pageLink in
                    pageLinkTile(
                        pageLink,
                        allPageLinks: pageLinks,
                        galleryIdentifier: summary.galleryIdentifier,
                        totalPageCount: summary.totalPageCount
                    )
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Returns cached pages for this gallery when the cache index has local records.
    private var cachedSummary: CachedGallerySummary? {
        imageCacheStore.gallerySummaries.first { $0.galleryIdentifier == result.identifier }
            ?? imageCacheStore.gallerySummaries.first { summary in
                summary.galleryIdentifier.site == result.identifier.site
                    && summary.galleryIdentifier.gid == result.identifier.gid
                    && summary.galleryIdentifier.token == result.identifier.token
            }
    }

    /// Converts cached page records into reader page links.
    private func cachedPageLinks(for summary: CachedGallerySummary) -> [EHGalleryPageLink] {
        summary.pageRecords.map { record in
            EHGalleryPageLink(
                pageNumber: record.pageNumber,
                pageURL: record.pageURL,
                thumbnailURL: record.thumbnailURL
            )
        }
    }

    /// Builds a page section title that uses the parsed gallery total when available.
    private func galleryPagesTitle(for detail: EHGalleryDetail) -> String {
        if let pageCount = detail.pageCount {
            return String(format: AppCopy.galleryPagesTitleFormat, String(pageCount))
        }
        return AppCopy.galleryPagesTitle
    }

    /// Builds the reader button title with the remembered page when available.
    private func galleryReadButtonTitle(resumePage: Int?, hasResume: Bool) -> String {
        if let resumePage {
            return String(format: AppCopy.galleryContinueReadingPage, String(resumePage))
        }
        return hasResume ? AppCopy.galleryContinueReading : AppCopy.galleryReadFromStart
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
    private func pageLinkTile(
        _ pageLink: EHGalleryPageLink,
        allPageLinks: [EHGalleryPageLink],
        galleryIdentifier: EHGalleryIdentifier,
        totalPageCount: Int?
    ) -> some View {
        Button {
            appNavigationStore.openReader(initialPageURL: pageLink.pageURL, pageLinks: allPageLinks, totalPageCount: totalPageCount)
        } label: {
            VStack(spacing: 6) {
                let thumbnail = pageThumbnailSource(for: pageLink, galleryIdentifier: galleryIdentifier)
                pageThumbnail(url: thumbnail.url, crop: thumbnail.crop, referer: thumbnail.referer)

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
    private func pageThumbnailSource(for pageLink: EHGalleryPageLink, galleryIdentifier: EHGalleryIdentifier) -> (url: URL?, crop: EHImageCrop?, referer: URL?) {
        if let cachedURL = imageCacheStore.cachedImageURL(for: galleryIdentifier, pageNumber: pageLink.pageNumber) {
            return (cachedURL, nil, nil)
        }
        return (pageLink.thumbnailURL, pageLink.thumbnailCrop, pageLink.pageURL)
    }

    /// Shows a stable thumbnail frame for one reader page.
    private func pageThumbnail(url: URL?, crop: EHImageCrop?, referer: URL?) -> some View {
        CachedRemoteImageView(url: url, referer: referer, crop: crop, contentMode: .fill, animationMode: .staticPreview, decodeMaxPixelSize: 420) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary.opacity(0.55))
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

                if detail.identifier.site.supportsOnlineFavorites {
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

    /// Shows the online favorite badge near the gallery title when known.
    @ViewBuilder
    private var siteFavoriteBadge: some View {
        if viewModel.isSiteFavorited == true {
            Label(siteFavoriteBadgeText, systemImage: "star.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(siteFavoriteBadgeText)
        }
    }

    /// Builds the online favorite badge text with the selected site category when available.
    private var siteFavoriteBadgeText: String {
        if let title = viewModel.siteFavoriteCategoryTitle, !title.isEmpty {
            return String(format: AppCopy.gallerySiteFavoriteCategoryFormat, title)
        }
        return AppCopy.gallerySiteFavoriteBadge
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
