import XCTest
@testable import MyEHViewer

/// Verifies baseline app copy used by the initial Chinese interface shell.
final class MyEHViewerTests: XCTestCase {
    /// Confirms the first visible navigation labels stay in Chinese.
    func testChineseShellCopy() {
        XCTAssertEqual(AppCopy.appName, "EH 阅读器")
        XCTAssertEqual(AppCopy.searchTitle, "搜索")
        XCTAssertEqual(AppCopy.readerTitle, "阅读")
        XCTAssertEqual(AppCopy.settingsTitle, "设置")
        XCTAssertEqual(EHSearchSource.frontPage.title, "首页")
        XCTAssertEqual(EHSearchSource.popular.title, "热门")
        XCTAssertEqual(EHSearchSource.watched.title, "关注")
        XCTAssertEqual(EHSearchSource.favorites.title, "收藏")
        XCTAssertEqual(AppCopy.libraryContinueReadingPage, "继续阅读第 %@ 页")
        XCTAssertEqual(AppCopy.galleryOpenInBrowser, "网页")
        XCTAssertEqual(AppCopy.searchResetFilters, "重置筛选")
    }

    /// Confirms reader preference labels stay localized for settings and toolbar menus.
    func testReaderPreferenceCopy() {
        XCTAssertEqual(ReaderFitMode.fitPage.title, "适合页面")
        XCTAssertEqual(ReaderFitMode.fitWidth.title, "贴合宽度")
        XCTAssertEqual(ReaderZoomLevel.x1.title, "100%")
        XCTAssertEqual(ReaderZoomLevel.x2.title, "200%")
        XCTAssertEqual(ReaderBackgroundMode.system.title, "跟随系统")
        XCTAssertEqual(ReaderBackgroundMode.dark.title, "深色")
        XCTAssertEqual(ReaderBackgroundMode.paper.title, "纸色")
        XCTAssertEqual(AppCopy.readerZoomMode, "缩放倍率")
        XCTAssertEqual(AppCopy.readerPageKnownFormat, "第 %@ 页 · 已知到 %@ 页")
        XCTAssertEqual(AppCopy.readerPageGrid, "目录")
        XCTAssertEqual(AppCopy.readerPageGridTitle, "页面目录")
        XCTAssertEqual(AppCopy.readerLinksMenu, "链接")
        XCTAssertEqual(AppCopy.readerCurrentPage, "当前页")
        XCTAssertEqual(AppCopy.readerGalleryPage, "图库页")
        XCTAssertEqual(AppCopy.readerJumpPageTitle, "跳到页码")
        XCTAssertEqual(AppCopy.readerJumpPageConfirm, "跳转")
        XCTAssertEqual(AppCopy.readerImageLoadFailed, "图片加载失败")
        XCTAssertEqual(AppCopy.readerImageRetry, "重新加载图片")
        XCTAssertEqual(AppCopy.readerToggleOrientation, "切换横竖屏")
        XCTAssertEqual(AppCopy.settingsImageCacheTitle, "图片缓存")
    }

    /// Confirms image cache data is saved, counted, read, and cleared.
    @MainActor
    func testImageCacheStoreSavesAndClearsData() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = ImageCacheStore(directoryURL: directoryURL)
        let imageURL = URL(string: "https://example.test/image.gif")!
        let data = Data([0x47, 0x49, 0x46, 0x38])

        XCTAssertNil(store.data(for: imageURL))
        XCTAssertEqual(store.snapshot, .empty)

        store.save(data, for: imageURL)

        XCTAssertEqual(store.data(for: imageURL), data)
        XCTAssertEqual(store.snapshot.fileCount, 1)
        XCTAssertEqual(store.snapshot.byteCount, Int64(data.count))

        store.clear()

        XCTAssertNil(store.data(for: imageURL))
        XCTAssertEqual(store.snapshot, .empty)
    }

    /// Confirms opening a reader route selects the reader tab.
    @MainActor
    func testAppNavigationStoreOpensReaderTab() {
        let store = AppNavigationStore()
        let pageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!

        store.openReader(initialPageURL: pageURL)

        XCTAssertEqual(store.selectedTab, .reader)
        XCTAssertEqual(store.readerRoute?.initialPageURL, pageURL)
        XCTAssertEqual(store.readerRoute?.pageLinks, [])
    }

    /// Confirms reader zoom persistence resolves unknown values safely.
    func testReaderZoomLevelResolution() {
        XCTAssertEqual(ReaderZoomLevel.resolved(rawValue: 1.5), .x15)
        XCTAssertEqual(ReaderZoomLevel.resolved(rawValue: 9.9), .x1)
        XCTAssertEqual(ReaderZoomLevel.x1.doubleTapTarget, .x2)
        XCTAssertEqual(ReaderZoomLevel.x2.doubleTapTarget, .x1)
    }

    /// Confirms tag search query text keeps namespace and quotes spaced names.
    func testTagSearchQuery() {
        XCTAssertEqual(EHTag(namespace: "group", name: "sample").searchQuery, "group:sample")
        XCTAssertEqual(EHTag(namespace: "group", name: "sample tag").searchQuery, "group:\"sample tag\"")
        XCTAssertEqual(EHTag(namespace: "", name: "sample tag").searchQuery, "\"sample tag\"")
    }
}
