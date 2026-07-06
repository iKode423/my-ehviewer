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

    /// Confirms a known page link can be loaded directly from reader controls.
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
        XCTAssertEqual(viewModel.knownLastPageNumber, 2)
    }

    /// Confirms a known page number can be loaded from the jump form.
    func testLoadPageNumberJumpsToKnownPage() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let secondURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let client = ReaderMockHTTPClient(responses: [
            firstURL: Self.firstPageHTML,
            secondURL: Self.secondPageHTML
        ])
        let viewModel = ReaderViewModel(
            initialPageURL: firstURL,
            pageLinks: [
                EHGalleryPageLink(pageNumber: 1, pageURL: firstURL),
                EHGalleryPageLink(pageNumber: 2, pageURL: secondURL)
            ],
            client: client
        )

        let loadedKnownPage = await viewModel.loadPageNumber(2)
        let loadedUnknownPage = await viewModel.loadPageNumber(9)

        XCTAssertTrue(loadedKnownPage)
        XCTAssertFalse(loadedUnknownPage)
        XCTAssertTrue(viewModel.canLoadPageNumber(1))
        XCTAssertFalse(viewModel.canLoadPageNumber(9))
        XCTAssertEqual(viewModel.imagePage?.pageNumber, 2)
    }

    /// Confirms page jump can fetch missing gallery page links before loading the target page.
    func testLoadPageNumberFetchesMissingGalleryLinks() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let secondURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let thumbnailPageURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/?p=1")!
        let client = ReaderMockHTTPClient(responses: [
            firstURL: Self.firstPageHTML,
            galleryURL: Self.galleryRootHTML,
            thumbnailPageURL: Self.gallerySecondThumbnailHTML,
            secondURL: Self.secondPageHTML
        ])
        let viewModel = ReaderViewModel(initialPageURL: firstURL, client: client)

        await viewModel.loadIfNeeded()
        let didLoadPage = await viewModel.loadPageNumber(2)

        XCTAssertTrue(didLoadPage)
        XCTAssertFalse(viewModel.isLoadingPageLinks)
        XCTAssertEqual(viewModel.sortedPageLinks.map(\.pageNumber), [1, 2])
        XCTAssertEqual(viewModel.imagePage?.pageNumber, 2)
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

    /// Confirms the visible page range does not show an upper bound below the current page.
    func testVisibleLastPageNumberIncludesCurrentPage() async {
        let pageURL = URL(string: "https://e-hentai.org/s/zzzzxxxxcc/100-27")!
        let client = ReaderMockHTTPClient(responses: [pageURL: Self.laterPageHTML])
        let viewModel = ReaderViewModel(
            initialPageURL: pageURL,
            pageLinks: [EHGalleryPageLink(pageNumber: 20, pageURL: URL(string: "https://e-hentai.org/s/known/100-20")!)],
            client: client
        )

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.knownLastPageNumber, 20)
        XCTAssertEqual(viewModel.visibleLastPageNumber, 27)
    }

    /// Confirms a cached reader page can open when the network page request fails.
    func testLoadUsesCachedImagePageWhenOffline() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let pageURL = URL(string: "https://e-hentai.org/s/zzzzxxxxcc/100-27")!
        let imageURL = URL(string: "https://example.test/27.webp")!
        cacheStore.save(
            Data([0x27]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: EHGalleryIdentifier(gid: 100, token: "abcdef1234"),
                galleryTitle: "Sample Gallery",
                pageNumber: 27,
                pageURL: pageURL,
                totalPageCount: 50,
                thumbnailURL: nil
            )
        )
        let viewModel = ReaderViewModel(
            initialPageURL: pageURL,
            client: ReaderMockHTTPClient(error: EHParseError.missingImageURL),
            cacheStore: cacheStore
        )

        await viewModel.loadIfNeeded()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.imagePage?.pageNumber, 27)
        XCTAssertEqual(viewModel.imagePage?.imageURL, imageURL)
        XCTAssertEqual(viewModel.totalPageCount, 50)
        XCTAssertEqual(viewModel.knownLastPageNumber, 50)
        XCTAssertEqual(cacheStore.data(for: imageURL), Data([0x27]))
    }

    /// Confirms cached reader navigation does not request page HTML again.
    func testCachedPreviousAndNextNavigationSkipsNetworkRequests() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 100, token: "abcdef1234")
        let firstPageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let secondPageURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let firstImageURL = URL(string: "https://example.test/1.webp")!
        let secondImageURL = URL(string: "https://example.test/2.webp")!
        let recorder = ReaderRecordingHTTPClient()

        cacheStore.save(
            Data([0x01]),
            for: firstImageURL,
            responseURL: firstImageURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Sample Gallery",
                pageNumber: 1,
                pageURL: firstPageURL,
                totalPageCount: 2,
                thumbnailURL: nil
            )
        )
        cacheStore.save(
            Data([0x02]),
            for: secondImageURL,
            responseURL: secondImageURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Sample Gallery",
                pageNumber: 2,
                pageURL: secondPageURL,
                totalPageCount: 2,
                thumbnailURL: nil
            )
        )
        let viewModel = ReaderViewModel(
            initialPageURL: firstPageURL,
            client: recorder,
            cacheStore: cacheStore
        )

        await viewModel.loadIfNeeded()
        await viewModel.loadNextPage()

        XCTAssertTrue(recorder.requestedURLs.isEmpty)
        XCTAssertEqual(viewModel.imagePage?.pageNumber, 2)
        XCTAssertEqual(viewModel.imagePage?.imageURL, secondImageURL)
    }

    /// Confirms retrying the current image advances the view reload token.
    func testReloadImageAdvancesRetryToken() async {
        let firstURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let client = ReaderMockHTTPClient(responses: [firstURL: Self.firstPageHTML])
        let viewModel = ReaderViewModel(initialPageURL: firstURL, client: client)

        viewModel.reloadImage()
        XCTAssertEqual(viewModel.imageReloadToken, 0)

        await viewModel.loadIfNeeded()
        let loadedToken = viewModel.imageReloadToken

        viewModel.reloadImage()

        XCTAssertEqual(viewModel.imageReloadToken, loadedToken + 1)
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

    private static let laterPageHTML = """
    <div id="i1"><h1>Sample Gallery - 27</h1></div>
    <div id="i2"><a id="prev" href="https://e-hentai.org/s/ddddeeeeff/100-26">Prev</a><a id="next" href="https://e-hentai.org/s/zzzzxxxxcc/100-27">Next</a></div>
    <div id="i3"><img id="img" src="https://example.test/27.webp" /></div>
    <div id="i5"><a href="https://e-hentai.org/g/100/abcdef1234/">Back</a></div>
    """

    private static let galleryRootHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1></div>
    <div id="gd3"><div id="gdc"><div class="cs ct2">Manga</div></div></div>
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><div title="1"></div></a></div>
    """

    private static let gallerySecondThumbnailHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1></div>
    <div id="gd3"><div id="gdc"><div class="cs ct2">Manga</div></div></div>
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/ddddeeeeff/100-2"><div title="2"></div></a></div>
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

/// Records reader page requests so cache-first tests can assert no network work.
private final class ReaderRecordingHTTPClient: EHHTTPClient {
    private(set) var requestedURLs: [URL] = []

    /// Records unexpected requests and returns an error.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        requestedURLs.append(url)
        throw EHParseError.missingImageURL
    }
}
