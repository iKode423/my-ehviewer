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
