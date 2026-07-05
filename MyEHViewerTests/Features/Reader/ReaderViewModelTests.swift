import XCTest
@testable import MyEHViewer

/// Verifies reader page loading and navigation without network access.
@MainActor
final class ReaderViewModelTests: XCTestCase {
    /// Confirms the initial image page is loaded and parsed.
    func testLoadIfNeededLoadsInitialPage() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let client = ReaderMockHTTPClient(responses: [firstURL: Self.firstPageHTML])
        let viewModel = ReaderViewModel(initialPageURL: firstURL, client: client)

        await viewModel.loadIfNeeded()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.imagePage?.pageNumber, 1)
        XCTAssertEqual(viewModel.imagePage?.imageURL.absoluteString, "https://example.test/1.webp")
        XCTAssertFalse(viewModel.canLoadPreviousPage)
        XCTAssertTrue(viewModel.canLoadNextPage)
    }

    /// Confirms the next page action replaces the current page.
    func testLoadNextPageUpdatesCurrentPage() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let secondURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let client = ReaderMockHTTPClient(responses: [
            firstURL: Self.firstPageHTML,
            secondURL: Self.secondPageHTML
        ])
        let viewModel = ReaderViewModel(initialPageURL: firstURL, client: client)

        await viewModel.loadIfNeeded()
        await viewModel.loadNextPage()

        XCTAssertEqual(viewModel.imagePage?.pageNumber, 2)
        XCTAssertEqual(viewModel.imagePage?.imageURL.absoluteString, "https://example.test/2.webp")
        XCTAssertTrue(viewModel.canLoadPreviousPage)
        XCTAssertFalse(viewModel.canLoadNextPage)
    }

    /// Confirms a known page link can be loaded directly from the jump menu.
    func testLoadPageJumpsToKnownPageLink() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let secondURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let client = ReaderMockHTTPClient(responses: [
            firstURL: Self.firstPageHTML,
            secondURL: Self.secondPageHTML
        ])
        let viewModel = ReaderViewModel(
            initialPageURL: firstURL,
            pageLinks: [
                EHGalleryPageLink(pageNumber: 2, pageURL: secondURL),
                EHGalleryPageLink(pageNumber: 1, pageURL: firstURL)
            ],
            client: client
        )

        await viewModel.loadPage(EHGalleryPageLink(pageNumber: 2, pageURL: secondURL))

        XCTAssertEqual(viewModel.imagePage?.pageNumber, 2)
        XCTAssertEqual(viewModel.sortedPageLinks.map(\.pageNumber), [1, 2])
    }

    /// Confirms loading a restored progress URL does not require known page links.
    func testLoadRestoredProgressURLWithoutPageLinks() async {
        let secondURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let client = ReaderMockHTTPClient(responses: [secondURL: Self.secondPageHTML])
        let viewModel = ReaderViewModel(initialPageURL: secondURL, client: client)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.imagePage?.pageNumber, 2)
        XCTAssertTrue(viewModel.sortedPageLinks.isEmpty)
    }

    /// Confirms loading errors are exposed as Chinese messages.
    func testLoadStoresErrorMessage() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let viewModel = ReaderViewModel(
            initialPageURL: firstURL,
            client: ReaderMockHTTPClient(error: EHParseError.missingImageURL)
        )

        await viewModel.loadIfNeeded()

        XCTAssertNil(viewModel.imagePage)
        XCTAssertEqual(viewModel.errorMessage, "阅读页缺少图片链接。")
    }

    private static let firstPageHTML = """
    <div id="i1"><h1>Sample Gallery - 1</h1></div>
    <div id="i2"><a id="prev" href="https://e-hentai.org/s/aaaabbbbcc/100-1">Prev</a><a id="next" href="https://e-hentai.org/s/ddddeeeeff/100-2">Next</a></div>
    <div id="i3"><img id="img" src="https://example.test/1.webp" /></div>
    <div id="i5"><a href="https://e-hentai.org/g/100/abcdef1234/">Back</a></div>
    <div id="i6"><a href="https://e-hentai.org/fullimg/100/1/token/file.jpg">Original</a></div>
    """

    private static let secondPageHTML = """
    <div id="i1"><h1>Sample Gallery - 2</h1></div>
    <div id="i2"><a id="prev" href="https://e-hentai.org/s/aaaabbbbcc/100-1">Prev</a><a id="next" href="https://e-hentai.org/s/ddddeeeeff/100-2">Next</a></div>
    <div id="i3"><img id="img" src="https://example.test/2.webp" /></div>
    <div id="i5"><a href="https://e-hentai.org/g/100/abcdef1234/">Back</a></div>
    """
}

/// Provides deterministic reader responses for tests.
private struct ReaderMockHTTPClient: EHHTTPClient {
    let responses: [URL: String]
    let error: Error?

    /// Creates successful reader responses keyed by URL.
    init(responses: [URL: String]) {
        self.responses = responses
        self.error = nil
    }

    /// Creates a failing reader response.
    init(error: Error) {
        self.responses = [:]
        self.error = error
    }

    /// Returns a configured reader page body.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        if let error {
            throw error
        }
        return EHHTTPResponse(url: url, statusCode: 200, body: responses[url] ?? "")
    }
}
