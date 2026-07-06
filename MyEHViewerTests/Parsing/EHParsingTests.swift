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

    /// Confirms search thumbnails can be recovered from CSS background styles.
    func testSearchPageParserReadsCSSBackgroundThumbnail() {
        let html = """
        <table class="itg gltc">
          <tr>
            <td class="gl1c glcat"><div class="cn ct2">Manga</div></td>
            <td class="gl2c"><div class="glthumb" style="background: url('https://example.test/thumb-css.jpg') center / cover no-repeat"></div></td>
            <td class="gl3c glname"><a href="https://e-hentai.org/g/100/abcdef1234/"><div class="glink">Sample Gallery</div></a></td>
            <td class="gl4c glhide"><div><a href="https://e-hentai.org/uploader/demo">demo</a></div><div>12 pages</div></td>
          </tr>
        </table>
        """

        let page = EHSearchPageParser().parse(html)

        XCTAssertEqual(page.results.first?.thumbnailURL?.absoluteString, "https://example.test/thumb-css.jpg")
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
        XCTAssertEqual(detail.pageCount, 2)
        XCTAssertEqual(detail.pageLinks.map(\.pageNumber), [1, 2])
        XCTAssertEqual(detail.pageLinks.map { $0.thumbnailURL?.absoluteString }, ["https://example.test/page-1.webp", "https://example.test/page-2.webp"])
        XCTAssertEqual(detail.thumbnailPageURLs.count, 1)
    }

    /// Confirms reader thumbnails can be recovered from CSS background styles.
    func testGalleryPageParserReadsCSSBackgroundThumbnail() throws {
        let html = """
        <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
        <div id="gd2"><h1 id="gn">Sample Gallery</h1></div>
        <div id="gd3"><div id="gdc"><div class="cs ct2">Manga</div></div></div>
        <div id="gdt">
          <a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><div style="width:120px;height:180px;background:transparent url(&quot;https://example.test/page-css.webp&quot;) -40px -60px no-repeat"><div title="1"></div></div></a>
        </div>
        """

        let detail = try EHGalleryPageParser().parse(
            html,
            sourceURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        )

        XCTAssertEqual(detail.pageLinks.first?.thumbnailURL?.absoluteString, "https://example.test/page-css.webp")
        XCTAssertEqual(detail.pageLinks.first?.thumbnailCrop, EHImageCrop(x: 40, y: 60, width: 120, height: 180))
    }

    /// Confirms parent CSS sprites are preferred over inner spacer image sources.
    func testGalleryPageParserReadsParentCSSSpriteThumbnails() throws {
        let html = """
        <div id="gleft"><div id="gd1"><div style="background: transparent url(https://example.test/cover.jpg) 0 0 no-repeat"></div></div></div>
        <div id="gd2"><h1 id="gn">Sample Gallery</h1></div>
        <div id="gdt">
          <div class="gdtm" style="width:120px;height:180px;background:transparent url(&quot;https://example.test/sprite.webp&quot;) 0 0 no-repeat">
            <a href="https://e-hentai.org/s/aaaabbbbcc/100-1"><img src="https://example.test/spacer.gif" width="120" height="180"></a>
          </div>
          <div class="gdtm" style="width:120px;height:180px;background:transparent url(&quot;https://example.test/sprite.webp&quot;) no-repeat -120px 0">
            <a href="https://e-hentai.org/s/aaaabbbbcc/100-2"><img src="https://example.test/spacer.gif" width="120" height="180"></a>
          </div>
          <div class="gdtm" style="width:120px;height:180px;background-image:url(&quot;https://example.test/sprite.webp&quot;);background-position-x:-240px;background-position-y:-180px">
            <a href="https://e-hentai.org/s/aaaabbbbcc/100-3"><img src="https://example.test/spacer.gif" width="120" height="180"></a>
          </div>
        </div>
        """

        let detail = try EHGalleryPageParser().parse(
            html,
            sourceURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        )

        XCTAssertEqual(detail.pageLinks.map(\.pageNumber), [1, 2, 3])
        XCTAssertEqual(detail.pageLinks.map { $0.thumbnailURL?.absoluteString }, Array(repeating: "https://example.test/sprite.webp", count: 3))
        XCTAssertEqual(detail.pageLinks.map(\.thumbnailCrop), [
            EHImageCrop(x: 0, y: 0, width: 120, height: 180),
            EHImageCrop(x: 120, y: 0, width: 120, height: 180),
            EHImageCrop(x: 240, y: 180, width: 120, height: 180)
        ])
    }

    /// Confirms online favorite popup forms preserve hidden fields and selected category.
    func testFavoritePopupParserBuildsSubmissionFields() {
        let html = """
        <form action="/gallerypopups.php?gid=100&amp;t=abcdef1234&amp;act=addfav" method="post">
          <input type="hidden" name="gid" value="100">
          <label><input type="radio" name="favcat" value="0">默认</label><br>
          <label><input type="radio" name="favcat" value="1" checked="checked">稍后阅读</label><br>
          <textarea name='favnote'>old &amp; note</textarea>
          <input type="submit" name="apply" value="Apply">
        </form>
        """

        let form = EHFavoritePopupParser().parse(
            html,
            sourceURL: URL(string: "https://e-hentai.org/gallerypopups.php?gid=100&t=abcdef1234&act=addfav")!
        )
        let fields = form.submissionFields(note: "new note")

        XCTAssertEqual(form.actionURL.absoluteString, "https://e-hentai.org/gallerypopups.php?gid=100&t=abcdef1234&act=addfav")
        XCTAssertEqual(form.categories.map(\.title), ["默认", "稍后阅读"])
        XCTAssertEqual(fields["gid"], "100")
        XCTAssertEqual(fields["favcat"], "1")
        XCTAssertEqual(fields["favnote"], "new note")
        XCTAssertEqual(fields["apply"], "Apply")
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
        XCTAssertEqual(EHSearchRequest(source: .frontPage, pageIndex: 0).url().absoluteString, "https://e-hentai.org/?jump=0")
        XCTAssertEqual(EHSearchRequest(source: .popular).url().absoluteString, "https://e-hentai.org/popular")
        XCTAssertEqual(EHSearchRequest(source: .watched).url().absoluteString, "https://e-hentai.org/watched")
        XCTAssertEqual(EHSearchRequest(source: .favorites).url().absoluteString, "https://e-hentai.org/favorites.php?favcat=all")
        XCTAssertEqual(EHSearchRequest(source: .favorites, pageIndex: 4).url().absoluteString, "https://e-hentai.org/favorites.php?favcat=all&jump=4")
    }
}
