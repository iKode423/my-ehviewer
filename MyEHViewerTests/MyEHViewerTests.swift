import ImageIO
import XCTest
import UniformTypeIdentifiers
import UIKit
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
        XCTAssertEqual(AppCopy.libraryFavorites, "本地收藏")
        XCTAssertEqual(AppCopy.librarySiteFavorites, "线上收藏")
        XCTAssertEqual(AppCopy.galleryLocalFavorite, "本地收藏")
        XCTAssertEqual(AppCopy.gallerySiteFavorite, "加入线上收藏")
        XCTAssertEqual(AppCopy.gallerySiteUnfavorite, "取消线上收藏")
        XCTAssertEqual(AppCopy.cacheManagementDeleteGallery, "删除缓存")
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

    /// Confirms duplicate image bytes reuse one cache file while preserving page progress.
    @MainActor
    func testImageCacheStoreDeduplicatesAliasesAndPageRecords() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 100, token: "abcdef1234")
        let firstImageURL = URL(string: "https://example.test/image-a.webp")!
        let secondImageURL = URL(string: "https://example.test/image-b.webp")!
        let firstResponseURL = URL(string: "https://cdn.test/image-a.webp")!
        let secondResponseURL = URL(string: "https://cdn.test/image-b.webp")!
        let data = Data([0x01, 0x02, 0x03, 0x04])

        store.save(
            data,
            for: firstImageURL,
            responseURL: firstResponseURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Sample Gallery",
                pageNumber: 1,
                pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!,
                totalPageCount: 2,
                thumbnailURL: URL(string: "https://example.test/cover.jpg")
            )
        )
        store.save(
            data,
            for: secondImageURL,
            responseURL: secondResponseURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Sample Gallery",
                pageNumber: 2,
                pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!,
                totalPageCount: 2,
                thumbnailURL: URL(string: "https://example.test/cover.jpg")
            )
        )

        let cacheFiles = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "index.json" }
        XCTAssertEqual(cacheFiles.count, 1)
        XCTAssertEqual(store.data(for: firstImageURL), data)
        XCTAssertEqual(store.data(for: secondResponseURL), data)
        XCTAssertEqual(store.snapshot.fileCount, 1)
        XCTAssertEqual(store.snapshot.byteCount, Int64(data.count))
        XCTAssertEqual(store.snapshot.galleryCount, 1)
        XCTAssertEqual(store.gallerySummaries.first?.cachedPageCount, 2)
        XCTAssertEqual(store.gallerySummaries.first?.totalPageCount, 2)
        XCTAssertEqual(store.cachedImageURL(for: identifier, pageNumber: 1), firstResponseURL)
        XCTAssertEqual(store.cachedImageURL(for: identifier, pageNumber: 2), secondResponseURL)

        store.clearGallery(identifier)

        XCTAssertNil(store.data(for: firstImageURL))
        XCTAssertNil(store.data(for: secondResponseURL))
        XCTAssertEqual(store.snapshot, .empty)
        XCTAssertTrue(store.gallerySummaries.isEmpty)
    }

    /// Confirms GIF preview rendering can force a static first frame.
    func testImageDataRendererCanRenderStaticGIFPreview() throws {
        let data = try makeAnimatedGIFData()

        let animatedImage = ImageDataRenderer.uiImage(from: data, allowsAnimation: true)
        let staticImage = ImageDataRenderer.uiImage(from: data, allowsAnimation: false)

        XCTAssertNotNil(animatedImage?.images)
        XCTAssertNil(staticImage?.images)
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

    /// Builds a tiny two-frame GIF fixture for renderer tests.
    private func makeAnimatedGIFData() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let colors: [UIColor] = [.red, .blue]
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1
            ]
        ] as CFDictionary
        let gifProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary

        CGImageDestinationSetProperties(destination, gifProperties)
        for color in colors {
            let image = renderer.image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), frameProperties)
        }

        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
