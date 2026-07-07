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

    /// Confirms thumbnail pagination merges additional reader links.
    func testLoadMorePageLinksMergesThumbnailPage() async {
        let firstURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let secondURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/?p=1")!
        let viewModel = GalleryDetailViewModel(
            pageURL: firstURL,
            client: GalleryMockHTTPClient(responses: [
                firstURL: Self.detailHTML,
                secondURL: Self.secondThumbnailPageHTML
            ])
        )

        await viewModel.reload()
        await viewModel.loadMorePageLinks()

        XCTAssertEqual(viewModel.detail?.pageLinks.map(\.pageNumber), [1, 2])
        XCTAssertFalse(viewModel.canLoadMorePageLinks)
    }

    /// Confirms all known thumbnail pages can be loaded in sequence.
    func testLoadAllPageLinksMergesEveryThumbnailPage() async {
        let firstURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let secondURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/?p=1")!
        let thirdURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/?p=2")!
        let viewModel = GalleryDetailViewModel(
            pageURL: firstURL,
            client: GalleryMockHTTPClient(responses: [
                firstURL: Self.multiPageDetailHTML,
                secondURL: Self.multiPageSecondThumbnailPageHTML,
                thirdURL: Self.multiPageThirdThumbnailPageHTML
            ])
        )

        await viewModel.reload()
        await viewModel.loadAllPageLinks()

        XCTAssertEqual(viewModel.detail?.pageLinks.map(\.pageNumber), [1, 2, 3])
        XCTAssertFalse(viewModel.canLoadMorePageLinks)
    }

    /// Confirms online favorite submission parses the popup form and posts preserved fields.
    func testAddSiteFavoriteSubmitsParsedPopupForm() async {
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let popupURL = EHGalleryIdentifier(gid: 100, token: "abcdef1234").favoritePopupURL()
        let formClient = GalleryFormRecorder()
        let viewModel = GalleryDetailViewModel(
            pageURL: galleryURL,
            client: GalleryMockHTTPClient(responses: [
                galleryURL: Self.detailHTML,
                popupURL: Self.favoritePopupHTML
            ]),
            formClient: formClient
        )

        await viewModel.reload()
        await viewModel.addSiteFavorite()

        XCTAssertFalse(viewModel.isUpdatingSiteFavorite)
        XCTAssertTrue(viewModel.siteFavoriteSucceeded)
        XCTAssertEqual(viewModel.isSiteFavorited, true)
        XCTAssertEqual(viewModel.siteFavoriteCategoryTitle, "测试")
        XCTAssertEqual(viewModel.siteFavoriteMessage, AppCopy.gallerySiteFavoriteSaved)
        XCTAssertEqual(formClient.postedURL?.absoluteString, "https://e-hentai.org/gallerypopups.php?gid=100&t=abcdef1234&act=addfav")
        XCTAssertEqual(formClient.postedFields["gid"], "100")
        XCTAssertEqual(formClient.postedFields["favcat"], "2")
        XCTAssertEqual(formClient.postedFields["favnote"], "")
        XCTAssertEqual(formClient.postedFields["apply"], "Apply")
    }

    /// Confirms online favorite removal submits the site's remove category value.
    func testRemoveSiteFavoriteSubmitsRemovalCategory() async {
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let popupURL = EHGalleryIdentifier(gid: 100, token: "abcdef1234").favoritePopupURL()
        let formClient = GalleryFormRecorder()
        let viewModel = GalleryDetailViewModel(
            pageURL: galleryURL,
            client: GalleryMockHTTPClient(responses: [
                galleryURL: Self.detailHTML,
                popupURL: Self.favoritePopupHTML
            ]),
            formClient: formClient
        )

        await viewModel.reload()
        await viewModel.removeSiteFavorite()

        XCTAssertFalse(viewModel.isUpdatingSiteFavorite)
        XCTAssertTrue(viewModel.siteFavoriteSucceeded)
        XCTAssertEqual(viewModel.isSiteFavorited, false)
        XCTAssertNil(viewModel.siteFavoriteCategoryTitle)
        XCTAssertEqual(viewModel.siteFavoriteMessage, AppCopy.gallerySiteFavoriteRemoved)
        XCTAssertEqual(formClient.postedFields["favcat"], "-1")
        XCTAssertEqual(formClient.postedFields["favnote"], "")
    }

    /// Confirms online favorite status can be read without submitting the form.
    func testRefreshSiteFavoriteStatusReadsSelectedCategory() async {
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let popupURL = EHGalleryIdentifier(gid: 100, token: "abcdef1234").favoritePopupURL()
        let viewModel = GalleryDetailViewModel(
            pageURL: galleryURL,
            client: GalleryMockHTTPClient(responses: [
                galleryURL: Self.detailHTML,
                popupURL: Self.favoritePopupHTML
            ])
        )

        await viewModel.reload()
        await viewModel.refreshSiteFavoriteStatus()

        XCTAssertFalse(viewModel.isLoadingSiteFavoriteStatus)
        XCTAssertEqual(viewModel.isSiteFavorited, true)
        XCTAssertEqual(viewModel.siteFavoriteCategoryTitle, "测试")
    }

    /// Confirms a default selected category without a remove option stays unfavorited.
    func testRefreshSiteFavoriteStatusIgnoresDefaultSelectedUnfavoritedCategory() async {
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let popupURL = EHGalleryIdentifier(gid: 100, token: "abcdef1234").favoritePopupURL()
        let viewModel = GalleryDetailViewModel(
            pageURL: galleryURL,
            client: GalleryMockHTTPClient(responses: [
                galleryURL: Self.detailHTML,
                popupURL: Self.defaultSelectedUnfavoritedPopupHTML
            ])
        )

        await viewModel.reload()
        await viewModel.refreshSiteFavoriteStatus()

        XCTAssertFalse(viewModel.isLoadingSiteFavoriteStatus)
        XCTAssertEqual(viewModel.isSiteFavorited, false)
        XCTAssertNil(viewModel.siteFavoriteCategoryTitle)
    }

    /// Confirms favorite status works when the site exposes removal through a submit button.
    func testRefreshSiteFavoriteStatusDetectsRemovalButtonFavorite() async {
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let popupURL = EHGalleryIdentifier(gid: 100, token: "abcdef1234").favoritePopupURL()
        let viewModel = GalleryDetailViewModel(
            pageURL: galleryURL,
            client: GalleryMockHTTPClient(responses: [
                galleryURL: Self.detailHTML,
                popupURL: Self.favoritedRemovalButtonPopupHTML
            ])
        )

        await viewModel.reload()
        await viewModel.refreshSiteFavoriteStatus()

        XCTAssertFalse(viewModel.isLoadingSiteFavoriteStatus)
        XCTAssertEqual(viewModel.isSiteFavorited, true)
        XCTAssertEqual(viewModel.siteFavoriteCategoryTitle, "Favorites 0")
    }

    /// Confirms a successful add marks the gallery favorited even when the popup has no selected category.
    func testAddSiteFavoriteMarksFavoriteAfterUnselectedPopupSubmission() async {
        let galleryURL = URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        let popupURL = EHGalleryIdentifier(gid: 100, token: "abcdef1234").favoritePopupURL()
        let viewModel = GalleryDetailViewModel(
            pageURL: galleryURL,
            client: GalleryMockHTTPClient(responses: [
                galleryURL: Self.detailHTML,
                popupURL: Self.unselectedFavoritePopupHTML
            ]),
            formClient: GalleryFormRecorder()
        )

        await viewModel.reload()
        await viewModel.addSiteFavorite()

        XCTAssertEqual(viewModel.isSiteFavorited, true)
        XCTAssertEqual(viewModel.siteFavoriteCategoryTitle, "默认")
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
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><div title="1"></div></a></div>
    """

    private static let secondThumbnailPageHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1><h1 id="gj">Sample JP</h1></div>
    <div id="gd3">
      <div id="gdc"><div class="cs ct2">Manga</div></div>
      <div id="gdn"><a href="https://e-hentai.org/uploader/demo">demo</a></div>
      <div id="gdd"><table><tr><td class="gdt1">Length:</td><td class="gdt2">2 pages</td></tr></table></div>
    </div>
    <div id="taglist"><table><tr><td class="tc">artist:</td><td><div class="gt"><a id="ta_artist:sample_artist" href="#">sample artist</a></div></td></tr></table></div>
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/ddddeeeeff/100-2"><div title="2"></div></a></div>
    """

    private static let multiPageDetailHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1><h1 id="gj">Sample JP</h1></div>
    <div id="gd3">
      <div id="gdc"><div class="cs ct2">Manga</div></div>
      <div id="gdn"><a href="https://e-hentai.org/uploader/demo">demo</a></div>
      <div id="gdd"><table><tr><td class="gdt1">Length:</td><td class="gdt2">3 pages</td></tr></table></div>
    </div>
    <div id="taglist"><table><tr><td class="tc">artist:</td><td><div class="gt"><a id="ta_artist:sample_artist" href="#">sample artist</a></div></td></tr></table></div>
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=2">3</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><div title="1"></div></a></div>
    """

    private static let multiPageSecondThumbnailPageHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1><h1 id="gj">Sample JP</h1></div>
    <div id="gd3">
      <div id="gdc"><div class="cs ct2">Manga</div></div>
      <div id="gdn"><a href="https://e-hentai.org/uploader/demo">demo</a></div>
      <div id="gdd"><table><tr><td class="gdt1">Length:</td><td class="gdt2">3 pages</td></tr></table></div>
    </div>
    <div id="taglist"><table><tr><td class="tc">artist:</td><td><div class="gt"><a id="ta_artist:sample_artist" href="#">sample artist</a></div></td></tr></table></div>
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=2">3</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/ddddeeeeff/100-2"><div title="2"></div></a></div>
    """

    private static let multiPageThirdThumbnailPageHTML = """
    <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
    <div id="gd2"><h1 id="gn">Sample Gallery</h1><h1 id="gj">Sample JP</h1></div>
    <div id="gd3">
      <div id="gdc"><div class="cs ct2">Manga</div></div>
      <div id="gdn"><a href="https://e-hentai.org/uploader/demo">demo</a></div>
      <div id="gdd"><table><tr><td class="gdt1">Length:</td><td class="gdt2">3 pages</td></tr></table></div>
    </div>
    <div id="taglist"><table><tr><td class="tc">artist:</td><td><div class="gt"><a id="ta_artist:sample_artist" href="#">sample artist</a></div></td></tr></table></div>
    <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=2">3</a></td></tr></table>
    <div id="gdt"><a href="https://e-hentai.org/s/gggghhhhii/100-3"><div title="3"></div></a></div>
    """

    private static let favoritePopupHTML = """
    <form action="/gallerypopups.php?gid=100&amp;t=abcdef1234&amp;act=addfav" method="post">
      <input type="hidden" name="gid" value="100">
      <label><input type="radio" name="favcat" value="0">默认</label><br>
      <label><input type="radio" name="favcat" value="2" checked="checked">测试</label><br>
      <label><input type="radio" name="favcat" value="-1">移除收藏</label><br>
      <textarea name="favnote">old note</textarea>
      <input type="submit" name="apply" value="Apply">
    </form>
    """

    private static let unselectedFavoritePopupHTML = """
    <form action="/gallerypopups.php?gid=100&amp;t=abcdef1234&amp;act=addfav" method="post">
      <input type="hidden" name="gid" value="100">
      <label><input type="radio" name="favcat" value="0">默认</label><br>
      <label><input type="radio" name="favcat" value="2">测试</label><br>
      <textarea name="favnote"></textarea>
      <input type="submit" name="apply" value="Apply">
    </form>
    """

    private static let defaultSelectedUnfavoritedPopupHTML = """
    <form action="/gallerypopups.php?gid=100&amp;t=abcdef1234&amp;act=addfav" method="post">
      <input type="hidden" name="gid" value="100">
      <label><input type="radio" name="favcat" value="0" checked="checked">Favorites 0</label><br>
      <label><input type="radio" name="favcat" value="2">测试</label><br>
      <textarea name="favnote"></textarea>
      <input type="submit" name="apply" value="Apply">
    </form>
    """

    private static let favoritedRemovalButtonPopupHTML = """
    <form action="/gallerypopups.php?gid=100&amp;t=abcdef1234&amp;act=addfav" method="post">
      <h1>Modify Favorite</h1>
      <input type="hidden" name="gid" value="100">
      <label><input type="radio" name="favcat" value="0" checked="checked">Favorites 0</label><br>
      <label><input type="radio" name="favcat" value="2">测试</label><br>
      <textarea name="favnote"></textarea>
      <input type="submit" name="favdel" value="Remove from Favorites">
    </form>
    """
}

/// Provides deterministic gallery detail responses for tests.
private struct GalleryMockHTTPClient: EHHTTPClient {
    let responses: [URL: String]
    let error: Error?

    /// Creates a successful gallery detail response.
    init(body: String, responseURL: URL) {
        self.responses = [responseURL: body]
        self.error = nil
    }

    /// Creates successful gallery detail responses keyed by URL.
    init(responses: [URL: String]) {
        self.responses = responses
        self.error = nil
    }

    /// Creates a failing gallery detail response.
    init(error: Error) {
        self.responses = [:]
        self.error = error
    }

    /// Returns the configured gallery detail response.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        if let error {
            throw error
        }
        return EHHTTPResponse(url: url, statusCode: 200, body: responses[url] ?? "")
    }
}

/// Records form submissions from gallery view model tests.
private final class GalleryFormRecorder: EHFormHTTPClient {
    private(set) var postedURL: URL?
    private(set) var postedFields: [String: String] = [:]

    /// Records the form request and returns a successful response.
    func postForm(_ url: URL, fields: [String: String]) async throws -> EHHTTPResponse {
        postedURL = url
        postedFields = fields
        return EHHTTPResponse(url: url, statusCode: 200, body: "ok")
    }
}
