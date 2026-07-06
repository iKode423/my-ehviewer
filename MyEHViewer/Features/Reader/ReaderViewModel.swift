import Combine
import Foundation

/// Loads image reader pages and tracks page navigation state.
@MainActor
final class ReaderViewModel: ObservableObject {
    let initialPageURL: URL?

    @Published private(set) var imagePage: EHImagePage?
    @Published private(set) var pageLinks: [EHGalleryPageLink]
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingPageLinks = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var imageReloadToken = 0
    @Published private(set) var totalPageCount: Int?

    private let client: EHHTTPClient
    private let parser: EHImagePageParser
    private let galleryParser: EHGalleryPageParser
    private let cacheStore: ImageCacheStore
    private var currentPageURL: URL?
    private var loadedGalleryPageURLStrings: Set<String> = []

    var sortedPageLinks: [EHGalleryPageLink] {
        pageLinks.sorted { $0.pageNumber < $1.pageNumber }
    }

    /// Returns the highest page number currently known from gallery page links.
    var knownLastPageNumber: Int? {
        [sortedPageLinks.map(\.pageNumber).max(), totalPageCount].compactMap(\.self).max()
    }

    /// Returns a visible upper page number that never falls behind the current page.
    var visibleLastPageNumber: Int? {
        guard let knownLastPageNumber else { return nil }
        guard let pageNumber = imagePage?.pageNumber else { return knownLastPageNumber }
        return max(knownLastPageNumber, pageNumber)
    }

    var canLoadPreviousPage: Bool {
        previousPageCandidateURL != nil
    }

    var canLoadNextPage: Bool {
        nextPageCandidateURL != nil
    }

    var canPresentPageJump: Bool {
        !sortedPageLinks.isEmpty || imagePage?.galleryURL != nil
    }

    /// Creates a reader view model with injectable dependencies for tests.
    init(
        initialPageURL: URL?,
        pageLinks: [EHGalleryPageLink] = [],
        totalPageCount: Int? = nil,
        client: EHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHImagePageParser = EHImagePageParser(),
        galleryParser: EHGalleryPageParser = EHGalleryPageParser(),
        cacheStore: ImageCacheStore = .shared
    ) {
        self.initialPageURL = initialPageURL
        self.pageLinks = pageLinks
        self.totalPageCount = totalPageCount
        self.currentPageURL = initialPageURL
        self.client = client
        self.parser = parser
        self.galleryParser = galleryParser
        self.cacheStore = cacheStore
    }

    /// Loads the initial page if the reader has not loaded it yet.
    func loadIfNeeded() async {
        guard imagePage == nil else { return }
        await reload()
    }

    /// Reloads the current page URL.
    func reload() async {
        guard let currentPageURL else { return }
        await load(currentPageURL)
    }

    /// Loads the previous image page when available.
    func loadPreviousPage() async {
        guard let previousPageURL = previousPageCandidateURL else { return }
        await load(previousPageURL)
    }

    /// Loads the next image page when available.
    func loadNextPage() async {
        guard let nextPageURL = nextPageCandidateURL else { return }
        await load(nextPageURL)
    }

    /// Loads a known gallery page link selected from reader controls.
    func loadPage(_ pageLink: EHGalleryPageLink) async {
        await load(pageLink.pageURL)
    }

    /// Requests a fresh load of the current image resource.
    func reloadImage() {
        guard imagePage != nil else { return }
        imageReloadToken += 1
    }

    /// Loads a known gallery page by its page number.
    @discardableResult
    func loadPageNumber(_ pageNumber: Int) async -> Bool {
        if pageLink(for: pageNumber) == nil {
            await loadAllPageLinksIfNeeded()
        }
        guard !isLoading, let pageLink = pageLink(for: pageNumber) else { return false }
        await loadPage(pageLink)
        return true
    }

    /// Loads every known gallery page link from the gallery thumbnail pages.
    func loadAllPageLinksIfNeeded() async {
        guard !isLoadingPageLinks, let galleryURL = imagePage?.galleryURL else { return }
        isLoadingPageLinks = true
        errorMessage = nil
        defer { isLoadingPageLinks = false }

        do {
            let response = try await client.get(galleryURL)
            let rootDetail = try galleryParser.parse(response.body, sourceURL: response.url)
            totalPageCount = rootDetail.pageCount ?? totalPageCount
            loadedGalleryPageURLStrings.insert(response.url.absoluteString)
            mergePageLinks(rootDetail.pageLinks)

            var thumbnailPageURLs = rootDetail.thumbnailPageURLs
            while let nextURL = thumbnailPageURLs.first(where: { !loadedGalleryPageURLStrings.contains($0.absoluteString) }) {
                let thumbnailResponse = try await client.get(nextURL)
                let detail = try galleryParser.parse(thumbnailResponse.body, sourceURL: thumbnailResponse.url)
                totalPageCount = detail.pageCount ?? totalPageCount
                loadedGalleryPageURLStrings.insert(thumbnailResponse.url.absoluteString)
                mergePageLinks(detail.pageLinks)
                thumbnailPageURLs = Array(Set(thumbnailPageURLs + detail.thumbnailPageURLs))
                    .sorted { $0.absoluteString < $1.absoluteString }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns true when the page number is available in known page links.
    func canLoadPageNumber(_ pageNumber: Int) -> Bool {
        pageLink(for: pageNumber) != nil
    }

    /// Returns the cached image URL for a known page preview when available.
    func cachedPreviewImageURL(for pageNumber: Int) -> URL? {
        guard let identifier = activeGalleryIdentifier else { return nil }
        return cacheStore.cachedImageURL(for: identifier, pageNumber: pageNumber)
    }

    /// Finds a known gallery page link by page number.
    private func pageLink(for pageNumber: Int) -> EHGalleryPageLink? {
        sortedPageLinks.first { $0.pageNumber == pageNumber }
    }

    /// Returns the best previous page URL from known page order, cache, or parsed HTML.
    private var previousPageCandidateURL: URL? {
        adjacentPageURL(offset: -1)
    }

    /// Returns the best next page URL from known page order, cache, or parsed HTML.
    private var nextPageCandidateURL: URL? {
        adjacentPageURL(offset: 1)
    }

    /// Finds an adjacent page URL while only disabling navigation at gallery boundaries.
    private func adjacentPageURL(offset: Int) -> URL? {
        guard let imagePage else { return nil }

        let targetPageNumber = imagePage.pageNumber + offset
        guard targetPageNumber > 0 else { return nil }
        if let knownLastPageNumber, targetPageNumber > knownLastPageNumber {
            return nil
        }

        if let knownPageURL = knownPageURL(for: targetPageNumber) {
            return knownPageURL
        }

        let parsedURL = offset < 0 ? imagePage.previousPageURL : imagePage.nextPageURL
        let activeURL = currentPageURL ?? imagePage.pageURL
        guard parsedURL != activeURL else { return nil }
        return parsedURL
    }

    /// Finds a page URL from loaded gallery links or cache records.
    private func knownPageURL(for pageNumber: Int) -> URL? {
        guard pageNumber > 0 else { return nil }
        if let pageLink = pageLink(for: pageNumber) {
            return pageLink.pageURL
        }
        guard let identifier = activeGalleryIdentifier else { return nil }
        return cacheStore.pageRecord(for: identifier, pageNumber: pageNumber)?.pageURL
    }

    /// Merges page links while keeping one URL for each page number.
    private func mergePageLinks(_ links: [EHGalleryPageLink]) {
        pageLinks = Dictionary(grouping: pageLinks + links, by: \.pageNumber)
            .compactMap { $0.value.first }
            .sorted { $0.pageNumber < $1.pageNumber }
    }

    /// Fetches, parses, and stores one reader page.
    private func load(_ url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if let cachedPage = cachedImagePage(for: url) {
            applyCachedPage(cachedPage)
            return
        }

        do {
            let response = try await client.get(url)
            imagePage = try parser.parse(response.body, sourceURL: response.url)
            imageReloadToken += 1
            currentPageURL = response.url
        } catch {
            if let cachedPage = cachedImagePage(for: url) {
                applyCachedPage(cachedPage)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Applies a cached page without touching the network.
    private func applyCachedPage(_ cachedPage: EHImagePage) {
        imagePage = cachedPage
        imageReloadToken += 1
        currentPageURL = cachedPage.pageURL
        errorMessage = nil
    }

    /// Builds a reader page from the local image cache when network HTML is unavailable.
    private func cachedImagePage(for url: URL) -> EHImagePage? {
        guard
            let record = cacheStore.pageRecord(for: url),
            cacheStore.containsData(for: record.imageURL)
        else {
            return nil
        }
        totalPageCount = record.totalPageCount ?? totalPageCount
        let previousURL = pageLink(for: record.pageNumber - 1)?.pageURL
            ?? cacheStore.pageRecord(for: record.galleryIdentifier, pageNumber: record.pageNumber - 1)?.pageURL
        let nextURL = pageLink(for: record.pageNumber + 1)?.pageURL
            ?? cacheStore.pageRecord(for: record.galleryIdentifier, pageNumber: record.pageNumber + 1)?.pageURL
        return EHImagePage(
            galleryID: record.galleryIdentifier.gid,
            pageNumber: record.pageNumber,
            pageURL: record.pageURL,
            title: record.galleryTitle,
            imageURL: record.imageURL,
            previousPageURL: previousURL,
            nextPageURL: nextURL,
            galleryURL: record.galleryIdentifier.url(),
            originalImageURL: nil
        )
    }

    private var activeGalleryIdentifier: EHGalleryIdentifier? {
        imagePage?.galleryURL.flatMap(EHGalleryIdentifier.init(galleryURL:)) ?? initialGalleryIdentifier
    }

    private var initialGalleryIdentifier: EHGalleryIdentifier? {
        pageLinks
            .compactMap { cacheStore.pageRecord(for: $0.pageURL)?.galleryIdentifier }
            .first
    }
}
