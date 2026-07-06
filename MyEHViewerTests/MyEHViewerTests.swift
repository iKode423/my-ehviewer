import ImageIO
import SwiftUI
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
        XCTAssertEqual(AppCopy.galleryDownloadPageFailedFormat, "第 %@ 页下载失败：%@")
        XCTAssertEqual(AppCopy.cacheManagementDeleteGallery, "删除缓存")
        XCTAssertEqual(AppCopy.cacheManagementStartUnfinished, "继续未完成下载")
        XCTAssertEqual(AppCopy.cacheManagementPauseAllDownloads, "暂停所有下载")
        XCTAssertEqual(AppCopy.cacheManagementProgressTitle, "下载进度")
        XCTAssertEqual(AppCopy.searchJumpPage, "跳页")
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
        XCTAssertEqual(AppCopy.readerBack, "返回")
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
        XCTAssertEqual(AppCopy.settingsAccentColor, "主题颜色")
        XCTAssertEqual(AppCopy.settingsClearNonGalleryImageCache, "清空非图库缓存")
    }

    /// Confirms the app accent color keeps the required default and persists as hex.
    func testAppAccentColorHexConversion() {
        XCTAssertEqual(AppAccentColor.defaultHex, "#00A8FF")
        XCTAssertEqual(AppAccentColor.hex(from: Color(red: 1.0, green: 0.0, blue: 0.0)), "#FF0000")
        XCTAssertEqual(AppAccentColor.hex(from: AppAccentColor.color(from: "#00a8ff")), "#00A8FF")
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

    /// Confirms clearing non-gallery cache keeps downloaded reader page images.
    @MainActor
    func testImageCacheStoreClearsOnlyNonGalleryImages() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 100, token: "abcdef1234")
        let thumbnailURL = URL(string: "https://example.test/thumb.jpg")!
        let imageURL = URL(string: "https://example.test/page-1.webp")!
        let imageData = Data([0x01, 0x02])

        store.save(Data([0x09]), for: thumbnailURL)
        store.save(
            imageData,
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Sample Gallery",
                pageNumber: 1,
                pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!,
                totalPageCount: 1,
                thumbnailURL: thumbnailURL
            )
        )

        XCTAssertTrue(store.hasNonGalleryImageCache)
        XCTAssertEqual(store.snapshot.fileCount, 2)

        store.clearNonGalleryImages()

        XCTAssertNil(store.data(for: thumbnailURL))
        XCTAssertEqual(store.data(for: imageURL), imageData)
        XCTAssertFalse(store.hasNonGalleryImageCache)
        XCTAssertEqual(store.snapshot.fileCount, 1)
        XCTAssertEqual(store.gallerySummaries.first?.cachedPageCount, 1)
    }

    /// Confirms GIF preview rendering can force a static first frame.
    func testImageDataRendererCanRenderStaticGIFPreview() throws {
        let data = try makeAnimatedGIFData()

        let animatedImage = ImageDataRenderer.uiImage(from: data, allowsAnimation: true)
        let staticImage = ImageDataRenderer.uiImage(from: data, allowsAnimation: false)

        XCTAssertNotNil(animatedImage?.images)
        XCTAssertNil(staticImage?.images)
    }

    /// Confirms opening a reader route keeps the current tab and presents a route.
    @MainActor
    func testAppNavigationStoreOpensReaderRouteWithoutChangingTab() {
        let store = AppNavigationStore()
        let pageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!

        store.selectedTab = .library
        store.openReader(initialPageURL: pageURL)

        XCTAssertEqual(store.selectedTab, .library)
        XCTAssertEqual(store.readerRoute?.initialPageURL, pageURL)
        XCTAssertEqual(store.readerRoute?.pageLinks, [])

        store.closeReader()

        XCTAssertNil(store.readerRoute)
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

/// Verifies gallery background download progress and failure handling.
@MainActor
final class GalleryDownloadManagerTests: XCTestCase {
    /// Confirms one failed page does not stop later pages from being cached.
    func testDownloadSkipsFailedPageAndContinues() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 100, token: "abcdef1234")
        let firstPageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!
        let secondPageURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!
        let thirdPageURL = URL(string: "https://e-hentai.org/s/eeeeffffgg/100-3")!
        let firstImageURL = URL(string: "https://example.test/1.webp")!
        let secondImageURL = URL(string: "https://example.test/2.webp")!
        let thirdImageURL = URL(string: "https://example.test/3.webp")!
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: [
                firstPageURL: Self.imagePageHTML(pageNumber: 1, imageURL: firstImageURL),
                secondPageURL: Self.imagePageHTML(pageNumber: 2, imageURL: secondImageURL),
                thirdPageURL: Self.imagePageHTML(pageNumber: 3, imageURL: thirdImageURL)
            ],
            dataResponses: [
                firstImageURL: .success(Data([0x01])),
                secondImageURL: .failure(EHNetworkError.unacceptableStatusCode(503)),
                thirdImageURL: .success(Data([0x03]))
            ]
        )
        let manager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Sample Gallery",
            japaneseTitle: nil,
            category: "Manga",
            coverURL: nil,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [
                EHGalleryPageLink(pageNumber: 1, pageURL: firstPageURL),
                EHGalleryPageLink(pageNumber: 2, pageURL: secondPageURL),
                EHGalleryPageLink(pageNumber: 3, pageURL: thirdPageURL)
            ],
            thumbnailPageURLs: [],
            pageCount: 3
        )

        manager.startDownload(detail: detail)
        await waitForFinishedDownload(manager: manager, identifier: identifier)

        let progress = try XCTUnwrap(manager.progress(for: identifier))
        XCTAssertFalse(progress.isRunning)
        XCTAssertEqual(progress.downloadedPageCount, 2)
        XCTAssertEqual(progress.totalPageCount, 3)
        XCTAssertEqual(progress.errorMessage, "第 2 页下载失败：服务器返回状态码 503。")
        XCTAssertEqual(cacheStore.data(for: firstImageURL), Data([0x01]))
        XCTAssertNil(cacheStore.data(for: secondImageURL))
        XCTAssertEqual(cacheStore.data(for: thirdImageURL), Data([0x03]))

        cacheStore.clearGallery(identifier)

        let clearedProgress = try XCTUnwrap(manager.progress(for: identifier))
        XCTAssertEqual(clearedProgress.downloadedPageCount, 0)
        XCTAssertEqual(clearedProgress.totalPageCount, 3)
    }

    /// Confirms a transient image failure is retried before the page is skipped.
    func testDownloadRetriesFailedImageBeforeSkipping() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 101, token: "abcdef1234")
        let firstPageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/101-1")!
        let firstImageURL = URL(string: "https://example.test/retry.webp")!
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: [
                firstPageURL: Self.imagePageHTML(pageNumber: 1, imageURL: firstImageURL)
            ],
            dataResponseSequences: [
                firstImageURL: [
                    .failure(EHNetworkError.unacceptableStatusCode(503)),
                    .success(Data([0x0A, 0x0B]))
                ]
            ]
        )
        let manager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Retry Gallery",
            japaneseTitle: nil,
            category: "Manga",
            coverURL: nil,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [
                EHGalleryPageLink(pageNumber: 1, pageURL: firstPageURL)
            ],
            thumbnailPageURLs: [],
            pageCount: 1
        )

        manager.startDownload(detail: detail)
        await waitForFinishedDownload(manager: manager, identifier: identifier)

        let progress = try XCTUnwrap(manager.progress(for: identifier))
        XCTAssertFalse(progress.isRunning)
        XCTAssertEqual(progress.downloadedPageCount, 1)
        XCTAssertNil(progress.errorMessage)
        XCTAssertEqual(cacheStore.data(for: firstImageURL), Data([0x0A, 0x0B]))
        XCTAssertEqual(client.dataRequestCount(for: firstImageURL), 2)
    }

    /// Confirms bulk cache downloads only run up to five gallery tasks at once.
    func testStartUnfinishedDownloadsLimitsConcurrentTasksToFive() {
        let cacheStore = ImageCacheStore(directoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = GalleryDownloadManager(
            client: GalleryDownloadMockHTTPClient(htmlResponses: [:], dataResponses: [:]),
            cacheStore: cacheStore,
            retryDelayRange: 0...0
        )
        let summaries = (1...7).map { index in
            CachedGallerySummary(
                galleryIdentifier: EHGalleryIdentifier(gid: 200 + index, token: "token\(index)"),
                title: "Gallery \(index)",
                thumbnailURL: nil,
                cachedPageCount: 1,
                totalPageCount: 2,
                byteCount: 1,
                updatedAt: Date(),
                pageRecords: []
            )
        }

        manager.startUnfinishedDownloads(from: summaries)

        XCTAssertEqual(manager.aggregateProgress?.activeDownloadCount, 5)
        XCTAssertEqual(manager.aggregateProgress?.queuedDownloadCount, 2)
        XCTAssertEqual(manager.aggregateProgress?.downloadedPageCount, 7)
        XCTAssertEqual(manager.aggregateProgress?.totalPageCount, 14)
    }

    /// Confirms pausing all downloads clears active and queued task state.
    func testPauseAllDownloadsStopsActiveAndQueuedTasks() {
        let cacheStore = ImageCacheStore(directoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = GalleryDownloadManager(
            client: GalleryDownloadMockHTTPClient(htmlResponses: [:], dataResponses: [:]),
            cacheStore: cacheStore,
            retryDelayRange: 0...0
        )
        let summaries = (1...6).map { index in
            CachedGallerySummary(
                galleryIdentifier: EHGalleryIdentifier(gid: 300 + index, token: "token\(index)"),
                title: "Gallery \(index)",
                thumbnailURL: nil,
                cachedPageCount: 1,
                totalPageCount: 3,
                byteCount: 1,
                updatedAt: Date(),
                pageRecords: []
            )
        }

        manager.startUnfinishedDownloads(from: summaries)
        manager.pauseAllDownloads()

        XCTAssertNil(manager.aggregateProgress)
        for summary in summaries {
            XCTAssertEqual(manager.progress(for: summary.galleryIdentifier)?.isRunning, false)
        }
    }

    /// Waits briefly for the manager's background task to finish.
    private func waitForFinishedDownload(manager: GalleryDownloadManager, identifier: EHGalleryIdentifier) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if manager.progress(for: identifier)?.isRunning == false {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Builds minimal reader HTML that the image page parser accepts.
    private static func imagePageHTML(pageNumber: Int, imageURL: URL) -> String {
        """
        <div id="i1"><h1>Sample Gallery - \(pageNumber)</h1></div>
        <div id="i2"><a id="prev" href="https://e-hentai.org/s/aaaabbbbcc/100-1">Prev</a><a id="next" href="https://e-hentai.org/s/eeeeffffgg/100-3">Next</a></div>
        <div id="i3"><img id="img" src="\(imageURL.absoluteString)" /></div>
        <div id="i5"><a href="https://e-hentai.org/g/100/abcdef1234/">Back</a></div>
        """
    }
}

/// Provides deterministic HTML and image responses for gallery download tests.
private final class GalleryDownloadMockHTTPClient: EHDataHTTPClient {
    private let htmlResponses: [URL: String]
    private var dataResponses: [URL: [Result<Data, Error>]]
    private var dataRequestCounts: [URL: Int] = [:]

    /// Creates a mock client with fixed page and image responses.
    init(htmlResponses: [URL: String], dataResponses: [URL: Result<Data, Error>]) {
        self.htmlResponses = htmlResponses
        self.dataResponses = dataResponses.mapValues { [$0] }
    }

    /// Creates a mock client with per-request image response sequences.
    init(htmlResponses: [URL: String], dataResponseSequences: [URL: [Result<Data, Error>]]) {
        self.htmlResponses = htmlResponses
        self.dataResponses = dataResponseSequences
    }

    /// Returns configured reader page HTML.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        guard let body = htmlResponses[url] else {
            throw EHParseError.missingImageURL
        }
        return EHHTTPResponse(url: url, statusCode: 200, body: body)
    }

    /// Returns configured image data or throws the configured failure.
    func data(_ url: URL) async throws -> EHDataResponse {
        dataRequestCounts[url, default: 0] += 1
        guard let response = nextDataResponse(for: url) else {
            throw EHNetworkError.unacceptableStatusCode(404)
        }

        switch response {
        case .success(let data):
            return EHDataResponse(url: url, statusCode: 200, data: data)
        case .failure(let error):
            throw error
        }
    }

    /// Returns how many times image data was requested for a URL.
    func dataRequestCount(for url: URL) -> Int {
        dataRequestCounts[url] ?? 0
    }

    /// Pops the next configured response, repeating the final value if needed.
    private func nextDataResponse(for url: URL) -> Result<Data, Error>? {
        guard var responses = dataResponses[url], let first = responses.first else {
            return nil
        }
        if responses.count > 1 {
            responses.removeFirst()
            dataResponses[url] = responses
        }
        return first
    }
}
