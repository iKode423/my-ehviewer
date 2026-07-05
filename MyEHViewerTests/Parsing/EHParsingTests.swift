import XCTest
@testable import MyEHViewer

/// Verifies HTML parsing against neutral fixtures that mirror the documented site structure.
final class EHParsingTests: XCTestCase {
    /// Confirms search rows, tags, thumbnails, and pagination are parsed.
    func testSearchPageParserReadsCompactRows() {
        let html = """
        <table class="itg gltc">
          <tr>
            <td class="gl1c glcat"><div class="cn ct2">Manga</div></td>
            <td class="gl2c"><div class="glthumb"><img src="data:image/gif;base64,stub" data-src="https://example.test/thumb.webp" /></div><div id="posted_100">2026-07-05</div></td>
            <td class="gl3c glname"><a href="https://e-hentai.org/g/100/abcdef1234/"><div class="glink">Sample &amp; Gallery</div><div><div class="gt" title="artist:sample artist">artist</div></div></a></td>
            <td class="gl4c glhide"><div><a href="https://e-hentai.org/uploader/demo">demo</a></div><div>12 pages</div></td>
          </tr>
        </table>
        <a id="unext" href="https://e-hentai.org/?next=100">Next</a>
        """

        let page = EHSearchPageParser().parse(html)

        XCTAssertEqual(page.results.count, 1)
        XCTAssertEqual(page.results[0].identifier.gid, 100)
        XCTAssertEqual(page.results[0].title, "Sample & Gallery")
        XCTAssertEqual(page.results[0].category, "Manga")
        XCTAssertEqual(page.results[0].thumbnailURL?.absoluteString, "https://example.test/thumb.webp")
        XCTAssertEqual(page.results[0].uploader, "demo")
        XCTAssertEqual(page.results[0].pageCountText, "12 pages")
        XCTAssertEqual(page.results[0].tags.first?.displayName, "artist:sample artist")
        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://e-hentai.org/?next=100")
    }

    /// Confirms gallery metadata, tags, and reader links are parsed.
    func testGalleryPageParserReadsDetailPage() throws {
        let html = """
        <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
        <div id="gd2"><h1 id="gn">Sample Gallery</h1><h1 id="gj">Sample JP</h1></div>
        <div id="gd3">
          <div id="gdc"><div class="cs ct2">Manga</div></div>
          <div id="gdn"><a href="https://e-hentai.org/uploader/demo">demo</a></div>
          <div id="gdd"><table>
            <tr><td class="gdt1">Posted:</td><td class="gdt2">2026-07-05</td></tr>
            <tr><td class="gdt1">Length:</td><td class="gdt2">2 pages</td></tr>
          </table></div>
          <div id="gdr"><span id="rating_count">2 ratings</span><div id="rating_label">Average: 4.50</div></div>
        </div>
        <div id="taglist"><table>
          <tr><td class="tc">artist:</td><td><div class="gt"><a id="ta_artist:sample_artist" href="#">sample artist</a></div></td></tr>
        </table></div>
        <table class="ptt"><tr><td><a href="https://e-hentai.org/g/100/abcdef1234/?p=1">2</a></td></tr></table>
        <div id="gdt">
          <a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><img data-src="https://example.test/page-1.webp" /><div title="1"></div></a>
          <a href="https://e-hentai.org/s/ddddeeeeff/100-2"><img src="https://example.test/page-2.webp" /><div title="2"></div></a>
        </div>
        """

        let detail = try EHGalleryPageParser().parse(
            html,
            sourceURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        )

        XCTAssertEqual(detail.identifier.gid, 100)
        XCTAssertEqual(detail.title, "Sample Gallery")
        XCTAssertEqual(detail.japaneseTitle, "Sample JP")
        XCTAssertEqual(detail.coverURL?.absoluteString, "https://example.test/cover.jpg")
        XCTAssertEqual(detail.uploader, "demo")
        XCTAssertEqual(detail.metadata.count, 2)
        XCTAssertEqual(detail.ratingCount, "2 ratings")
        XCTAssertEqual(detail.tags.first?.displayName, "artist:sample artist")
        XCTAssertEqual(detail.pageLinks.map(\.pageNumber), [1, 2])
        XCTAssertEqual(detail.pageLinks.map { $0.thumbnailURL?.absoluteString }, ["https://example.test/page-1.webp", "https://example.test/page-2.webp"])
        XCTAssertEqual(detail.thumbnailPageURLs.count, 1)
    }

    /// Confirms image URL, navigation, and original image links are parsed.
    func testImagePageParserReadsReaderPage() throws {
        let html = """
        <div id="i1"><h1>Sample Gallery - 1</h1></div>
        <div id="i2"><a id="prev" href="https://e-hentai.org/s/aaaabbbbcc/100-1">Prev</a><a id="next" href="https://e-hentai.org/s/ddddeeeeff/100-2">Next</a></div>
        <div id="i3"><a href="https://e-hentai.org/s/ddddeeeeff/100-2"><img id="img" src="https://example.test/image.webp" /></a></div>
        <div id="i5"><div><a href="https://e-hentai.org/g/100/abcdef1234/">Back</a></div></div>
        <div id="i6"><a href="https://e-hentai.org/fullimg/100/1/token/file.jpg">Original</a></div>
        """

        let page = try EHImagePageParser().parse(
            html,
            sourceURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        )

        XCTAssertEqual(page.galleryID, 100)
        XCTAssertEqual(page.pageNumber, 1)
        XCTAssertEqual(page.title, "Sample Gallery - 1")
        XCTAssertEqual(page.imageURL.absoluteString, "https://example.test/image.webp")
        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://e-hentai.org/s/ddddeeeeff/100-2")
        XCTAssertEqual(page.galleryURL?.absoluteString, "https://e-hentai.org/g/100/abcdef1234/")
        XCTAssertEqual(page.originalImageURL?.absoluteString, "https://e-hentai.org/fullimg/100/1/token/file.jpg")
    }

    /// Confirms advanced search options map to documented query names.
    func testSearchRequestBuildsAdvancedURL() {
        let request = EHSearchRequest(
            keyword: "sample",
            excludedCategories: [.misc, .western],
            browseExpunged: true,
            requireTorrent: true,
            minimumPages: 10,
            maximumPages: 20,
            minimumRating: 4,
            disableLanguageFilter: true,
            disableUploaderFilter: false,
            disableTagFilter: true,
            cursor: .next(100)
        )

        let components = URLComponents(url: request.url(), resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: components?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

        XCTAssertEqual(items["f_search"], "sample")
        XCTAssertEqual(items["f_cats"], "513")
        XCTAssertEqual(items["advsearch"], "1")
        XCTAssertEqual(items["f_sh"], "on")
        XCTAssertEqual(items["f_sto"], "on")
        XCTAssertEqual(items["f_spf"], "10")
        XCTAssertEqual(items["f_spt"], "20")
        XCTAssertEqual(items["f_srdd"], "4")
        XCTAssertEqual(items["f_sfl"], "on")
        XCTAssertEqual(items["f_sft"], "on")
        XCTAssertEqual(items["next"], "100")
    }

    /// Confirms alternate browse sources use the documented endpoint paths.
    func testSearchRequestBuildsSourceURLs() {
        XCTAssertEqual(EHSearchRequest(source: .frontPage).url().absoluteString, "https://e-hentai.org/")
        XCTAssertEqual(EHSearchRequest(source: .popular).url().absoluteString, "https://e-hentai.org/popular")
        XCTAssertEqual(EHSearchRequest(source: .watched).url().absoluteString, "https://e-hentai.org/watched")
        XCTAssertEqual(EHSearchRequest(source: .favorites).url().absoluteString, "https://e-hentai.org/favorites.php")
    }
}
