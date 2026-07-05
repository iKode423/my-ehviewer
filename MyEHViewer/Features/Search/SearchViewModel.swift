import Combine
import Foundation

/// Manages search query state, loading, parsing, and pagination.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var source = EHSearchSource.frontPage
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
    @Published private(set) var recentQueries: [String] = []

    private let client: EHHTTPClient
    private let parser: EHSearchPageParser
    private let userDefaults: UserDefaults
    private let recentQueriesKey: String
    private var lastURL: URL?
    private var lastRequestedURL: URL?

    /// Creates a view model with injectable dependencies for tests.
    init(
        initialQuery: String = "",
        client: EHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHSearchPageParser = EHSearchPageParser(),
        userDefaults: UserDefaults = .standard,
        recentQueriesKey: String = "Search.recentQueries"
    ) {
        self.query = initialQuery
        self.client = client
        self.parser = parser
        self.userDefaults = userDefaults
        self.recentQueriesKey = recentQueriesKey
        self.recentQueries = userDefaults.stringArray(forKey: recentQueriesKey) ?? []
    }

    /// Loads the first page for the current query and filter state.
    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if await load(currentRequest(trimmedQuery: trimmedQuery).url()) {
            recordRecentQuery(trimmedQuery)
        }
    }

    /// Starts searching only once when a view opens from a prefilled query.
    func searchIfNeeded() async {
        guard !hasSearched else { return }
        await search()
    }

    /// Reuses a previous query and starts a new search.
    func useRecentQuery(_ recentQuery: String) async {
        query = recentQuery
        await search()
    }

    /// Clears all locally saved recent search queries.
    func clearRecentQueries() {
        recentQueries = []
        userDefaults.removeObject(forKey: recentQueriesKey)
    }

    /// Reloads the last successful request, or starts a new search if needed.
    func refresh() async {
        await load(lastURL ?? lastRequestedURL ?? currentRequest().url())
    }

    /// Retries the most recent attempted request.
    func retry() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if await load(lastRequestedURL ?? currentRequest(trimmedQuery: trimmedQuery).url()) {
            recordRecentQuery(trimmedQuery)
        }
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
    @discardableResult
    private func load(_ url: URL) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        hasSearched = true
        lastRequestedURL = url
        defer { isLoading = false }

        do {
            let response = try await client.get(url)
            let page = parser.parse(response.body)
            results = page.results
            nextPageURL = page.nextPageURL
            previousPageURL = page.previousPageURL
            lastURL = response.url
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Saves a successful non-empty query at the front of recent searches.
    private func recordRecentQuery(_ recentQuery: String) {
        guard !recentQuery.isEmpty else { return }

        recentQueries.removeAll { $0.caseInsensitiveCompare(recentQuery) == .orderedSame }
        recentQueries.insert(recentQuery, at: 0)
        recentQueries = Array(recentQueries.prefix(10))
        userDefaults.set(recentQueries, forKey: recentQueriesKey)
    }

    /// Builds a request from the current search controls.
    private func currentRequest(trimmedQuery: String? = nil) -> EHSearchRequest {
        EHSearchRequest(
            source: source,
            keyword: trimmedQuery ?? query.trimmingCharacters(in: .whitespacesAndNewlines),
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
    }
}
