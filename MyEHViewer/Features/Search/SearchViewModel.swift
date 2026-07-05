import Combine
import Foundation

/// Manages search query state, loading, parsing, and pagination.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var excludedCategories: Set<EHGalleryCategory> = []
    @Published var browseExpunged = false
    @Published var requireTorrent = false
    @Published var minimumPagesText = ""
    @Published var maximumPagesText = ""
    @Published var minimumRating = 0
    @Published var disableLanguageFilter = false
    @Published var disableUploaderFilter = false
    @Published var disableTagFilter = false
    @Published private(set) var results: [EHSearchResult] = []
    @Published private(set) var nextPageURL: URL?
    @Published private(set) var previousPageURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSearched = false

    private let client: EHHTTPClient
    private let parser: EHSearchPageParser
    private var lastURL: URL?

    /// Creates a view model with injectable dependencies for tests.
    init(client: EHHTTPClient = URLSessionEHHTTPClient(), parser: EHSearchPageParser = EHSearchPageParser()) {
        self.client = client
        self.parser = parser
    }

    /// Loads the first page for the current query and filter state.
    func search() async {
        let request = EHSearchRequest(
            keyword: query,
            excludedCategories: excludedCategories,
            browseExpunged: browseExpunged,
            requireTorrent: requireTorrent,
            minimumPages: Int(minimumPagesText),
            maximumPages: Int(maximumPagesText),
            minimumRating: minimumRating == 0 ? nil : minimumRating,
            disableLanguageFilter: disableLanguageFilter,
            disableUploaderFilter: disableUploaderFilter,
            disableTagFilter: disableTagFilter
        )
        await load(request.url())
    }

    /// Reloads the last successful request, or starts a new search if needed.
    func refresh() async {
        await load(lastURL ?? EHSearchRequest(keyword: query).url())
    }

    /// Loads the next cursor page when the site exposes one.
    func loadNextPage() async {
        guard let nextPageURL else { return }
        await load(nextPageURL)
    }

    /// Loads the previous cursor page when the site exposes one.
    func loadPreviousPage() async {
        guard let previousPageURL else { return }
        await load(previousPageURL)
    }

    /// Performs the request and replaces the current page with parsed results.
    private func load(_ url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        hasSearched = true
        defer { isLoading = false }

        do {
            let response = try await client.get(url)
            let page = parser.parse(response.body)
            results = page.results
            nextPageURL = page.nextPageURL
            previousPageURL = page.previousPageURL
            lastURL = response.url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
