import XCTest
@testable import MyEHViewer

/// Verifies gallery detail loading without network access.
@MainActor
final class GalleryDetailViewModelTests: XCTestCase {
    /// Confirms detail HTML populates gallery state.
    func testReloadLoadsGalleryDetail() async {
        let url = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let viewModel = GalleryDetailViewModel(pageURL: url, client: GalleryMockHTTPClient(body: Self.detailHTML, responseURL: url))

        await viewModel.reload()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.detail?.title, "Sample Gallery")
        XCTAssertEqual(viewModel.detail?.metadata.count, 1)
        XCTAssertEqual(viewModel.detail?.tags.first?.displayName, "artist:sample artist")
        XCTAssertEqual(viewModel.detail?.pageLinks.first?.pageNumber, 1)
    }

    /// Confirms loading errors are exposed as user-facing messages.
    func testReloadStoresErrorMessage() async {
        let url = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let viewModel = GalleryDetailViewModel(pageURL: url, client: GalleryMockHTTPClient(error: EHParseError.missingGalleryTitle))

        await viewModel.reload()

        XCTAssertNil(viewModel.detail)
        XCTAssertEqual(viewModel.errorMessage, "图库页面缺少标题。")
    }

    private static let detailHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1><h1 id="gj">Sample JP</h1></div>
    <div id="gd3">
      <div id="gdc"><div class="cs ct2">Manga</div></div>
      <div id="gdn"><a href="https://e-hentai.org/uploader/demo">demo</a></div>
      <div id="gdd"><table><tr><td class="gdt1">Length:</td><td class="gdt2">2 pages</td></tr></table></div>
      <div id="gdr"><span id="rating_count">2 ratings</span><div id="rating_label">Average: 4.50</div></div>
    </div>
    <div id="taglist"><table><tr><td class="tc">artist:</td><td><div class="gt"><a id="ta_artist:sample_artist" href="#">sample artist</a></div></td></tr></table></div>
    <div id="gdt"><a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><div title="1"></div></a></div>
    """
}

/// Provides deterministic gallery detail responses for tests.
private struct GalleryMockHTTPClient: EHHTTPClient {
    let body: String
    let responseURL: URL
    let error: Error?

    /// Creates a successful gallery detail response.
    init(body: String, responseURL: URL) {
        self.body = body
        self.responseURL = responseURL
        self.error = nil
    }

    /// Creates a failing gallery detail response.
    init(error: Error) {
        self.body = ""
        self.responseURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        self.error = error
    }

    /// Returns the configured gallery detail response.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        if let error {
            throw error
        }
        return EHHTTPResponse(url: responseURL, statusCode: 200, body: body)
    }
}

