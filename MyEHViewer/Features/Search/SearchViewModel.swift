import Combine
import Foundation

/// Manages search query state, loading, parsing, and pagination.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var site: ContentSite
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
    @Published private(set) var currentPageNumber = 1

    /// Returns true when any category or advanced filter is enabled.
    var hasActiveFilters: Bool {
        !excludedCategories.isEmpty ||
            browseExpunged ||
            requireTorrent ||
            !minimumPagesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !maximumPagesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            minimumRating != 0 ||
            disableLanguageFilter ||
            disableUploaderFilter ||
            disableTagFilter
    }

    private let client: EHHTTPClient
    private let parser: EHSearchPageParser
    private let hitomiDataSource: HitomiDataSource
    private let userDefaults: UserDefaults
    private let recentQueriesKey: String
    private var lastURL: URL?
    private var lastRequestedURL: URL?

    var availableSources: [EHSearchSource] {
        site.supportedSearchSources
    }

    /// Creates a view model with injectable dependencies for tests.
    init(
        initialQuery: String = "",
        initialSource: EHSearchSource = .frontPage,
        initialSite: ContentSite? = nil,
        client: EHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHSearchPageParser = EHSearchPageParser(),
        hitomiDataSource: HitomiDataSource = HitomiDataSource(),
        userDefaults: UserDefaults = .standard,
        recentQueriesKey: String = "Search.recentQueries"
    ) {
        self.query = initialQuery
        let resolvedSite = initialSite ?? ContentSite.resolved(rawValue: userDefaults.string(forKey: ContentSite.storageKey) ?? "")
        self.site = resolvedSite
        self.source = resolvedSite.supportedSearchSources.contains(initialSource) ? initialSource : .frontPage
        self.client = client
        self.parser = parser
        self.hitomiDataSource = hitomiDataSource
        self.userDefaults = userDefaults
        self.recentQueriesKey = recentQueriesKey
        self.recentQueries = userDefaults.stringArray(forKey: recentQueriesKey) ?? []
    }

    /// Switches the active content site and clears stale search results from the previous site.
    func setSite(_ site: ContentSite) {
        guard self.site != site else { return }
        self.site = site
        source = site.supportedSearchSources.contains(source) ? source : .frontPage
        results = []
        nextPageURL = nil
        previousPageURL = nil
        errorMessage = nil
        hasSearched = false
        currentPageNumber = 1
        lastURL = nil
        lastRequestedURL = nil
    }

    /// Loads the first page for the current query and filter state.
    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let didLoad: Bool
        switch site {
        case .eHentai:
            didLoad = await load(currentRequest(trimmedQuery: trimmedQuery).url(baseURL: site.baseURL))
        case .hitomi:
            didLoad = await loadHitomiPage(number: 1, trimmedQuery: trimmedQuery)
        }
        if didLoad {
            currentPageNumber = 1
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

    /// Clears filter controls without changing the query or browse source.
    func resetFilters() {
        excludedCategories = []
        browseExpunged = false
        requireTorrent = false
        minimumPagesText = ""
        maximumPagesText = ""
        minimumRating = 0
        disableLanguageFilter = false
        disableUploaderFilter = false
        disableTagFilter = false
    }

    /// Reloads the last successful request, or starts a new search if needed.
    func refresh() async {
        if site == .hitomi {
            await loadHitomiPage(number: currentPageNumber)
        } else {
            await load(lastURL ?? lastRequestedURL ?? currentRequest().url(baseURL: site.baseURL))
        }
    }

    /// Retries the most recent attempted request.
    func retry() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if site == .hitomi {
            if await loadHitomiPage(number: currentPageNumber, trimmedQuery: trimmedQuery) {
                recordRecentQuery(trimmedQuery)
            }
            return
        }
        if await load(lastRequestedURL ?? currentRequest(trimmedQuery: trimmedQuery).url(baseURL: site.baseURL)) {
            recordRecentQuery(trimmedQuery)
        }
    }

    /// Loads the next cursor page when the site exposes one.
    func loadNextPage() async {
        if site == .hitomi {
            let pageNumber = currentPageNumber + 1
            if await loadHitomiPage(number: pageNumber) {
                currentPageNumber = pageNumber
            }
            return
        }
        guard let nextPageURL else { return }
        if await load(nextPageURL) {
            currentPageNumber += 1
        }
    }

    /// Loads the previous cursor page when the site exposes one.
    func loadPreviousPage() async {
        if site == .hitomi {
            let pageNumber = max(1, currentPageNumber - 1)
            guard pageNumber != currentPageNumber else { return }
            if await loadHitomiPage(number: pageNumber) {
                currentPageNumber = pageNumber
            }
            return
        }
        guard let previousPageURL else { return }
        if await load(previousPageURL) {
            currentPageNumber = max(1, currentPageNumber - 1)
        }
    }

    /// Loads a numbered result page using the current search controls.
    func loadPage(number: Int) async {
        guard number > 0 else { return }
        if await loadSearchPage(number: number) {
            currentPageNumber = number
        }
    }

    /// Routes the current search to the active site's page loader.
    @discardableResult
    private func loadSearchPage(number: Int, trimmedQuery: String? = nil) async -> Bool {
        switch site {
        case .eHentai:
            return await load(currentRequest(trimmedQuery: trimmedQuery, pageIndex: number - 1).url(baseURL: site.baseURL))
        case .hitomi:
            return await loadHitomiPage(number: number, trimmedQuery: trimmedQuery)
        }
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

    /// Loads one Hitomi browse page through the static gallery index.
    @discardableResult
    private func loadHitomiPage(number: Int, trimmedQuery: String? = nil) async -> Bool {
        guard !isLoading else { return false }
        let safePageNumber = max(1, number)
        isLoading = true
        errorMessage = nil
        hasSearched = true
        lastRequestedURL = hitomiPageURL(number: safePageNumber)
        defer { isLoading = false }

        do {
            let page = try await hitomiDataSource.searchPage(
                keyword: trimmedQuery ?? query.trimmingCharacters(in: .whitespacesAndNewlines),
                pageNumber: safePageNumber
            )
            results = page.results
            nextPageURL = page.nextPageURL
            previousPageURL = page.previousPageURL
            lastURL = hitomiPageURL(number: safePageNumber)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Builds a synthetic URL used only to preserve Hitomi pagination state.
    private func hitomiPageURL(number: Int) -> URL {
        var components = URLComponents(url: ContentSite.hitomi.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "page", value: String(max(1, number)))]
        return components.url ?? ContentSite.hitomi.baseURL
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
    private func currentRequest(trimmedQuery: String? = nil, pageIndex: Int? = nil) -> EHSearchRequest {
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
            disableTagFilter: disableTagFilter,
            pageIndex: pageIndex
        )
    }
}
