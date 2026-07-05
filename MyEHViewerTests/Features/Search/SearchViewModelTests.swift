import XCTest
@testable import MyEHViewer

/// Verifies the search view model without touching the network.
@MainActor
final class SearchViewModelTests: XCTestCase {
    /// Confirms a successful search populates result and pagination state.
    func testSearchLoadsParsedResults() async {
        let viewModel = SearchViewModel(client: MockHTTPClient(body: Self.searchHTML), userDefaults: makeUserDefaults())
        viewModel.query = "sample"

        await viewModel.search()

        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.title, "Sample Gallery")
        XCTAssertEqual(viewModel.nextPageURL?.absoluteString, "https://e-hentai.org/?next=100")
    }

    /// Confirms network errors become Chinese user-facing messages.
    func testSearchStoresErrorMessage() async {
        let viewModel = SearchViewModel(client: MockHTTPClient(error: EHNetworkError.unacceptableStatusCode(503)), userDefaults: makeUserDefaults())

        await viewModel.search()

        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "服务器返回状态码 503。")
    }

    /// Confirms retry keeps the full failed URL including advanced filters.
    func testRetryKeepsFailedFilteredRequest() async {
        let recorder = SearchRequestRecorder()
        let viewModel = SearchViewModel(
            client: MockHTTPClient(error: EHNetworkError.unacceptableStatusCode(503), recorder: recorder),
            userDefaults: makeUserDefaults()
        )
        viewModel.query = "sample"
        viewModel.minimumPagesText = "10"
        viewModel.disableTagFilter = true

        await viewModel.search()
        await viewModel.retry()

        XCTAssertEqual(recorder.requestedURLs.count, 2)
        XCTAssertEqual(recorder.requestedURLs[0], recorder.requestedURLs[1])

        let queryItems = URLComponents(url: recorder.requestedURLs[1], resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryByName = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(queryByName["f_search"], "sample")
        XCTAssertEqual(queryByName["advsearch"], "1")
        XCTAssertEqual(queryByName["f_spf"], "10")
        XCTAssertEqual(queryByName["f_sft"], "on")
    }

    /// Confirms successful non-empty queries are persisted as recent searches.
    func testSuccessfulSearchRecordsRecentQuery() async {
        let defaults = makeUserDefaults()
        let viewModel = SearchViewModel(client: MockHTTPClient(body: Self.searchHTML), userDefaults: defaults, recentQueriesKey: "recent-test")
        viewModel.query = " sample "

        await viewModel.search()

        let restored = SearchViewModel(client: MockHTTPClient(body: Self.searchHTML), userDefaults: defaults, recentQueriesKey: "recent-test")
        XCTAssertEqual(restored.recentQueries, ["sample"])
    }

    /// Confirms an initial query can auto-search exactly once.
    func testSearchIfNeededUsesInitialQueryOnce() async {
        let recorder = SearchRequestRecorder()
        let viewModel = SearchViewModel(
            initialQuery: "group:sample",
            client: MockHTTPClient(body: Self.searchHTML, recorder: recorder),
            userDefaults: makeUserDefaults()
        )

        await viewModel.searchIfNeeded()
        await viewModel.searchIfNeeded()

        XCTAssertEqual(recorder.requestedURLs.count, 1)
        let queryItems = URLComponents(url: recorder.requestedURLs[0], resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryByName = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(queryByName["f_search"], "group:sample")
        XCTAssertEqual(viewModel.results.count, 1)
    }

    /// Confirms recent queries can be cleared from local persistence.
    func testClearRecentQueriesRemovesPersistedState() async {
        let defaults = makeUserDefaults()
        let viewModel = SearchViewModel(client: MockHTTPClient(body: Self.searchHTML), userDefaults: defaults, recentQueriesKey: "recent-clear-test")
        viewModel.query = "sample"

        await viewModel.search()
        viewModel.clearRecentQueries()

        let restored = SearchViewModel(client: MockHTTPClient(body: Self.searchHTML), userDefaults: defaults, recentQueriesKey: "recent-clear-test")
        XCTAssertTrue(restored.recentQueries.isEmpty)
    }

    /// Creates isolated defaults for each test run.
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "SearchViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static let searchHTML = """
    <table class="itg gltc">
      <tr>
        <td class="gl1c glcat"><div class="cn ct2">Manga</div></td>
        <td class="gl2c"><div class="glthumb"><img data-src="https://example.test/thumb.webp" /></div></td>
        <td class="gl3c glname"><a href="https://e-hentai.org/g/100/abcdef1234/"><div class="glink">Sample Gallery</div></a></td>
        <td class="gl4c glhide"><div><a href="https://e-hentai.org/uploader/demo">demo</a></div><div>12 pages</div></td>
      </tr>
    </table>
    <a id="unext" href="https://e-hentai.org/?next=100">Next</a>
    """
}

/// Provides deterministic HTML or error responses for view-model tests.
private struct MockHTTPClient: EHHTTPClient {
    let body: String
    let error: Error?
    let recorder: SearchRequestRecorder?

    /// Creates a successful mock response.
    init(body: String, recorder: SearchRequestRecorder? = nil) {
        self.body = body
        self.error = nil
        self.recorder = recorder
    }

    /// Creates a failing mock response.
    init(error: Error, recorder: SearchRequestRecorder? = nil) {
        self.body = ""
        self.error = error
        self.recorder = recorder
    }

    /// Returns the configured mock response.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        recorder?.append(url)
        if let error {
            throw error
        }
        return EHHTTPResponse(url: url, statusCode: 200, body: body)
    }
}

/// Records requested URLs across async mock client calls.
private final class SearchRequestRecorder: @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []

    /// Appends one requested URL.
    func append(_ url: URL) {
        requestedURLs.append(url)
    }
}
