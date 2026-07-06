import Combine
import Foundation

/// Loads image reader pages and tracks page navigation state.
@MainActor
final class ReaderViewModel: ObservableObject {
    let initialPageURL: URL?
    let pageLinks: [EHGalleryPageLink]

    @Published private(set) var imagePage: EHImagePage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var imageReloadToken = 0

    private let client: EHHTTPClient
    private let parser: EHImagePageParser
    private var currentPageURL: URL?

    var sortedPageLinks: [EHGalleryPageLink] {
        pageLinks.sorted { $0.pageNumber < $1.pageNumber }
    }

    /// Returns the highest page number currently known from gallery page links.
    var knownLastPageNumber: Int? {
        sortedPageLinks.map(\.pageNumber).max()
    }

    /// Returns a visible upper page number that never falls behind the current page.
    var visibleLastPageNumber: Int? {
        guard let knownLastPageNumber else { return nil }
        guard let pageNumber = imagePage?.pageNumber else { return knownLastPageNumber }
        return max(knownLastPageNumber, pageNumber)
    }

    var canLoadPreviousPage: Bool {
        guard let previousPageURL = imagePage?.previousPageURL else { return false }
        return previousPageURL != currentPageURL
    }

    var canLoadNextPage: Bool {
        guard let nextPageURL = imagePage?.nextPageURL else { return false }
        return nextPageURL != currentPageURL
    }

    /// Creates a reader view model with injectable dependencies for tests.
    init(
        initialPageURL: URL?,
        pageLinks: [EHGalleryPageLink] = [],
        client: EHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHImagePageParser = EHImagePageParser()
    ) {
        self.initialPageURL = initialPageURL
        self.pageLinks = pageLinks
        self.currentPageURL = initialPageURL
        self.client = client
        self.parser = parser
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
        guard canLoadPreviousPage, let previousPageURL = imagePage?.previousPageURL else { return }
        await load(previousPageURL)
    }

    /// Loads the next image page when available.
    func loadNextPage() async {
        guard canLoadNextPage, let nextPageURL = imagePage?.nextPageURL else { return }
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
        guard !isLoading, let pageLink = pageLink(for: pageNumber) else { return false }
        await loadPage(pageLink)
        return true
    }

    /// Returns true when the page number is available in known page links.
    func canLoadPageNumber(_ pageNumber: Int) -> Bool {
        pageLink(for: pageNumber) != nil
    }

    /// Finds a known gallery page link by page number.
    private func pageLink(for pageNumber: Int) -> EHGalleryPageLink? {
        sortedPageLinks.first { $0.pageNumber == pageNumber }
    }

    /// Fetches, parses, and stores one reader page.
    private func load(_ url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.get(url)
            imagePage = try parser.parse(response.body, sourceURL: response.url)
            imageReloadToken += 1
            currentPageURL = response.url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
