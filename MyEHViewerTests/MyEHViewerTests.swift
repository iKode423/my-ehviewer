import CryptoKit
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
        XCTAssertEqual(AppCopy.commonOK, "好")
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
        XCTAssertEqual(AppCopy.gallerySiteFavoriteBadge, "已加入线上收藏")
        XCTAssertEqual(AppCopy.galleryDownloadPageFailedFormat, "第 %@ 页下载失败：%@")
        XCTAssertEqual(AppCopy.cacheManagementDeleteGallery, "删除缓存")
        XCTAssertEqual(AppCopy.cacheManagementStartUnfinished, "继续未完成下载")
        XCTAssertEqual(AppCopy.cacheManagementPauseAllDownloads, "暂停所有下载")
        XCTAssertEqual(AppCopy.cacheManagementProgressTitle, "下载进度")
        XCTAssertEqual(AppCopy.searchJumpPage, "跳页")
        XCTAssertEqual(AppCopy.settingsContentSiteTitle, "图库来源")
        XCTAssertEqual(AppCopy.galleryRelatedTitle, "关联图库")
        XCTAssertEqual(AppCopy.searchResultsCountFormat, "共 %@ 个结果")
        XCTAssertEqual(AppCopy.searchApproxResultsCountFormat, "约 %@ 个结果")
        XCTAssertEqual(AppCopy.searchTotalPagesFormat, "%@ 页")
        XCTAssertEqual(ContentSite.hitomi.title, "Hitomi")
    }

    /// Confirms Hitomi gallery URLs produce site-scoped identifiers.
    func testHitomiGalleryIdentifierParsing() {
        let canonicalURL = URL(string: "https://hitomi.la/galleries/4037854.html")!
        let publicURL = URL(string: "https://hitomi.la/doujinshi/sample-title-4037854.html")!

        XCTAssertEqual(EHGalleryIdentifier(galleryURL: canonicalURL)?.site, .hitomi)
        XCTAssertEqual(EHGalleryIdentifier(galleryURL: canonicalURL)?.id, "hitomi-4037854")
        XCTAssertEqual(EHGalleryIdentifier(galleryURL: publicURL)?.site, .hitomi)
        XCTAssertFalse(ContentSite.hitomi.supportsOnlineFavorites)
        XCTAssertEqual(ContentSite.hitomi.supportedSearchSources, [.frontPage])
    }

    /// Confirms QR navigation accepts only supported gallery detail hosts.
    func testSupportedGalleryURLParsingRejectsUnrelatedHosts() throws {
        let eHentaiURL = try XCTUnwrap(URL(string: "https://e-hentai.org/g/100/abcdef1234/"))
        let hitomiURL = try XCTUnwrap(URL(string: "https://hitomi.la/manga/sample-200.html"))
        let unrelatedURL = try XCTUnwrap(URL(string: "https://example.com/g/100/abcdef1234/"))

        XCTAssertEqual(EHGalleryIdentifier(supportedGalleryURL: eHentaiURL), EHGalleryIdentifier(gid: 100, token: "abcdef1234"))
        XCTAssertEqual(EHGalleryIdentifier(supportedGalleryURL: hitomiURL), EHGalleryIdentifier(gid: 200, token: "hitomi", site: .hitomi))
        XCTAssertNil(EHGalleryIdentifier(supportedGalleryURL: unrelatedURL))
    }

    /// Confirms Hitomi front page search reads one full nozomi page by byte range.
    @MainActor
    func testHitomiFrontPageSearchReadsNozomiPage() async throws {
        let galleryIDs = Array(4_037_800..<4_037_825)
        let rangeData = HitomiSearchMockData(query: "miku", galleryIDs: [], frontPageIDs: galleryIDs)
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: Dictionary(uniqueKeysWithValues: galleryIDs.map { galleryID in
                (galleryID, Self.hitomiGalleryInfoJSON(id: galleryID, title: "Gallery \(galleryID)"))
            })
        )
        let dataSource = HitomiDataSource(client: client) { url, range in
            try rangeData.data(for: url, range: range)
        }

        let page = try await dataSource.searchPage(keyword: "", pageNumber: 1)

        XCTAssertEqual(page.results.map(\.identifier.gid), galleryIDs)
        XCTAssertEqual(client.requestedGalleryInfoIDs, galleryIDs)
    }

    /// Confirms Hitomi keyword search reads the galleries index instead of filtering only one browse page.
    @MainActor
    func testHitomiKeywordSearchUsesGalleryIndex() async throws {
        let indexVersion = "1783485646"
        let query = "miku"
        let galleryIDs = [4_037_854, 4_037_855]
        let rangeData = HitomiSearchMockData(query: query, galleryIDs: galleryIDs)
        let client = HitomiMockHTTPClient(
            indexVersion: indexVersion,
            galleryInfos: [
                4_037_854: Self.hitomiGalleryInfoJSON(id: 4_037_854, title: "Miku First"),
                4_037_855: Self.hitomiGalleryInfoJSON(id: 4_037_855, title: "Miku Second")
            ]
        )
        let dataSource = HitomiDataSource(client: client) { url, range in
            try rangeData.data(for: url, range: range)
        }

        let page = try await dataSource.searchPage(keyword: query, pageNumber: 1)

        XCTAssertEqual(page.results.map(\.identifier.gid), galleryIDs)
        XCTAssertEqual(page.results.map(\.identifier.site), [.hitomi, .hitomi])
        XCTAssertEqual(page.totalResultCount, 2)
        XCTAssertEqual(page.totalPageCount, 1)
        XCTAssertNil(page.nextPageURL)
        XCTAssertEqual(client.requestedGalleryInfoIDs, galleryIDs)
    }

    /// Confirms quoted Hitomi namespace terms keep spaces inside one search term.
    @MainActor
    func testHitomiQuotedGroupSearchUsesNozomiTerm() async throws {
        let galleryID = 4_037_854
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(id: galleryID, title: "Grouped Gallery")
            ],
            nozomiGalleryIDsByPath: [
                "/n/group/baby lop-all.nozomi": [galleryID]
            ]
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }

        let page = try await dataSource.searchPage(keyword: #"group:"Baby Lop""#, pageNumber: 1)

        XCTAssertEqual(page.results.map(\.identifier.gid), [galleryID])
        XCTAssertEqual(client.requestedDataPaths, ["/n/group/baby lop-all.nozomi"])
    }

    /// Confirms search rows surface language before other tags.
    func testSearchRowTagsPreferLanguage() {
        let result = EHSearchResult(
            identifier: EHGalleryIdentifier(gid: 100, token: "abcdef1234"),
            title: "Sample Gallery",
            category: "Manga",
            pageURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!,
            thumbnailURL: nil,
            uploader: nil,
            postedText: nil,
            pageCountText: nil,
            tags: [
                EHTag(namespace: "artist", name: "sample"),
                EHTag(namespace: "language", name: "english"),
                EHTag(namespace: "parody", name: "original")
            ]
        )

        XCTAssertEqual(result.searchRowTags.map(\.displayName), [
            "language:english",
            "artist:sample",
            "parody:original"
        ])
    }


    /// Confirms Hitomi search, cover, and preview thumbnails use AVIF when available.
    @MainActor
    func testHitomiSearchAndDetailUseAVIFThumbnails() async throws {
        let galleryID = 4_037_854
        let hash = "0123456789abcdef"
        let expectedThumbnailURL = "https://tn.gold-usergeneratedcontent.net/avifsmalltn/f/de/\(hash).avif"
        let rangeData = HitomiSearchMockData(query: "", galleryIDs: [], frontPageIDs: [galleryID])
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(id: galleryID, title: "AVIF Gallery", hash: hash, hasAVIF: true)
            ]
        )
        let dataSource = HitomiDataSource(client: client) { url, range in
            try rangeData.data(for: url, range: range)
        }

        let searchPage = try await dataSource.searchPage(keyword: "", pageNumber: 1)
        let detail = try await dataSource.galleryDetail(from: URL(string: "https://hitomi.la/galleries/\(galleryID).html")!)

        XCTAssertEqual(searchPage.results.first?.thumbnailURL?.absoluteString, expectedThumbnailURL)
        XCTAssertEqual(searchPage.results.first?.searchRowTags.first?.displayName, "language:english")
        XCTAssertNil(searchPage.totalResultCount)
        XCTAssertNil(searchPage.totalPageCount)
        XCTAssertEqual(detail.coverURL?.absoluteString, expectedThumbnailURL)
        XCTAssertEqual(detail.pageLinks.first?.thumbnailURL?.absoluteString, expectedThumbnailURL)
    }

    /// Confirms Hitomi details expose group, related galleries, and bounded preview batches.
    @MainActor
    func testHitomiDetailLimitsPreviewAddsGroupAndRelatedGalleries() async throws {
        let galleryID = 4_037_854
        let relatedID = 4_037_855
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(
                    id: galleryID,
                    title: "Main Gallery",
                    fileCount: 45,
                    groups: ["Baby Lop"],
                    characters: ["Alice"],
                    relatedIDs: [relatedID]
                ),
                relatedID: Self.hitomiGalleryInfoJSON(id: relatedID, title: "Related Gallery")
            ]
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }

        let detail = try await dataSource.galleryDetail(from: URL(string: "https://hitomi.la/galleries/\(galleryID).html")!)
        let groupMetadata = try XCTUnwrap(detail.metadata.first { $0.key == "Group" })
        let nextBatch = try await dataSource.galleryPageLinks(
            from: URL(string: "https://hitomi.la/galleries/\(galleryID).html")!,
            startPage: 21
        )

        XCTAssertEqual(detail.pageLinks.count, 20)
        XCTAssertEqual(detail.pageCount, 45)
        XCTAssertEqual(groupMetadata.value, "Baby Lop")
        XCTAssertEqual(groupMetadata.searchTags.first?.searchQuery, "group:\"Baby Lop\"")
        XCTAssertTrue(detail.tags.contains(EHTag(namespace: "group", name: "Baby Lop")))
        XCTAssertTrue(detail.tags.contains(EHTag(namespace: "character", name: "Alice")))
        XCTAssertEqual(detail.relatedGalleries.map(\.identifier.gid), [relatedID])
        XCTAssertEqual(detail.relatedGalleries.first?.title, "Related Gallery")
        XCTAssertEqual(nextBatch.map(\.pageNumber), Array(21...40))
    }

    /// Confirms older Hitomi gallery JSON accepts numeric ids and numeric tag flags.
    @MainActor
    func testHitomiLegacyGalleryInfoDecodesNumericFields() async throws {
        let galleryID = 895_262
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: """
                {
                  "id": 895262,
                  "title": "Mahjong Tenshi Nodocchi Kanzen Kaikin",
                  "type": "doujinshi",
                  "language": "chinese",
                  "galleryurl": "/doujinshi/mahjong-tenshi-nodocchi-kanzen-kaikin-中文-154628-895262.html",
                  "files": [{"name":"000.jpg","hash":"68b8899b33ecc92786867dd2da8874effdf2767918199e0481dc9c8a0dbea8d7","hasavif":1}],
                  "tags": [{"tag":"big breasts","female":1,"male":""}]
                }
                """
            ]
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }
        let pageURL = try XCTUnwrap(URL(string: "https://hitomi.la/doujinshi/mahjong-tenshi-nodocchi-kanzen-kaikin-%E4%B8%AD%E6%96%87-154628-895262.html#1"))

        let detail = try await dataSource.galleryDetail(from: pageURL)

        XCTAssertEqual(detail.identifier.gid, galleryID)
        XCTAssertEqual(detail.title, "Mahjong Tenshi Nodocchi Kanzen Kaikin")
        XCTAssertTrue(detail.tags.contains(EHTag(namespace: "female", name: "big breasts")))
        XCTAssertEqual(detail.pageCount, 1)
    }


    /// Confirms Hitomi image pages prefer current AVIF hosts when gallery metadata supports AVIF.
    @MainActor
    func testHitomiImagePageUsesCurrentAVIFURL() async throws {
        let galleryID = 4_037_854
        let hash = "0123456789abcdef"
        let hashCode = Int("fde", radix: 16)!
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(id: galleryID, title: "AVIF Gallery", hash: hash, hasAVIF: true)
            ],
            imageContextScript: Self.hitomiImageContextScript(pathPrefix: "1783501202/", suffixValue: 0, codes: [hashCode + 1])
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }

        let page = try await dataSource.imagePage(from: URL(string: "https://hitomi.la/hitomi/s/\(galleryID)-1")!)

        XCTAssertEqual(page.imageURL.absoluteString, "https://a1.gold-usergeneratedcontent.net/1783501202/\(hashCode)/\(hash).avif")
    }

    /// Confirms concurrent page batches share one gallery info request and later calls reuse its cached result.
    @MainActor
    func testHitomiConcurrentPageBatchesShareGalleryInfoRequest() async throws {
        let galleryID = 4_037_854
        let galleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(galleryID).html"))
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(id: galleryID, title: "Shared Gallery", fileCount: 3)
            ],
            galleryInfoDelayNanoseconds: 50_000_000
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }

        let firstTask = Task { @MainActor in
            try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)
        }
        let secondTask = Task { @MainActor in
            try await dataSource.galleryPageLinks(from: galleryURL, startPage: 2, limit: 1)
        }
        let thirdTask = Task { @MainActor in
            try await dataSource.galleryPageLinks(from: galleryURL, startPage: 3, limit: 1)
        }

        let firstBatch = try await firstTask.value
        let secondBatch = try await secondTask.value
        let thirdBatch = try await thirdTask.value
        let cachedBatch = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)

        XCTAssertEqual(firstBatch.map(\.pageNumber), [1])
        XCTAssertEqual(secondBatch.map(\.pageNumber), [2])
        XCTAssertEqual(thirdBatch.map(\.pageNumber), [3])
        XCTAssertEqual(cachedBatch.map(\.pageNumber), [1])
        XCTAssertEqual(client.requestedGalleryInfoIDs, [galleryID])
    }

    /// Confirms cancelling one caller does not wait for or cancel another caller's shared request.
    @MainActor
    func testHitomiSharedGalleryInfoRequestSupportsIndependentCancellation() async throws {
        let galleryID = 4_037_854
        let galleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(galleryID).html"))
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(id: galleryID, title: "Shared Gallery", fileCount: 2)
            ],
            galleryInfoDelayNanoseconds: 200_000_000
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }
        let cancelledTask = Task { @MainActor in
            do {
                _ = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let requestDeadline = Date().addingTimeInterval(1)
        while client.requestedGalleryInfoIDs.isEmpty, Date() < requestDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(client.requestedGalleryInfoIDs, [galleryID])
        let remainingTask = Task { @MainActor in
            try await dataSource.galleryPageLinks(from: galleryURL, startPage: 2, limit: 1)
        }

        await Task.yield()
        cancelledTask.cancel()

        let wasCancelled = await cancelledTask.value
        let remainingBatch = try await remainingTask.value
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(remainingBatch.map(\.pageNumber), [2])
        XCTAssertEqual(client.requestedGalleryInfoIDs, [galleryID])
    }

    /// Confirms a failed shared gallery info request is removed so a later request can retry.
    @MainActor
    func testHitomiFailedGalleryInfoRequestIsNotCached() async throws {
        let galleryID = 4_037_854
        let galleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(galleryID).html"))
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: [
                galleryID: Self.hitomiGalleryInfoJSON(id: galleryID, title: "Retry Gallery")
            ],
            galleryInfoDelayNanoseconds: 50_000_000,
            galleryInfoFailuresRemainingByID: [galleryID: 1]
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }

        let firstTask = Task { @MainActor in
            do {
                _ = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)
                return false
            } catch {
                return true
            }
        }
        let secondTask = Task { @MainActor in
            do {
                _ = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)
                return false
            } catch {
                return true
            }
        }

        let firstFailed = await firstTask.value
        let secondFailed = await secondTask.value
        let retriedBatch = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)

        XCTAssertTrue(firstFailed)
        XCTAssertTrue(secondFailed)
        XCTAssertEqual(retriedBatch.map(\.pageNumber), [1])
        XCTAssertEqual(client.requestedGalleryInfoIDs, [galleryID, galleryID])
    }

    /// Confirms the gallery info cache evicts older entries after reaching its fixed capacity.
    @MainActor
    func testHitomiGalleryInfoCacheHasBoundedCapacity() async throws {
        let galleryIDs = Array(4_037_850...4_037_858)
        let galleryInfos = Dictionary(uniqueKeysWithValues: galleryIDs.map { galleryID in
            (galleryID, Self.hitomiGalleryInfoJSON(id: galleryID, title: "Gallery \(galleryID)"))
        })
        let client = HitomiMockHTTPClient(indexVersion: "1783485646", galleryInfos: galleryInfos)
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }

        for galleryID in galleryIDs {
            let galleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(galleryID).html"))
            _ = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 1, limit: 1)
        }

        let firstGalleryID = try XCTUnwrap(galleryIDs.first)
        let firstGalleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(firstGalleryID).html"))
        _ = try await dataSource.galleryPageLinks(from: firstGalleryURL, startPage: 1, limit: 1)

        XCTAssertEqual(client.requestedGalleryInfoIDs.count, galleryIDs.count + 1)
        XCTAssertEqual(client.requestedGalleryInfoIDs.filter { $0 == firstGalleryID }.count, 2)
    }

    /// Confirms related galleries cannot evict the main detail before its page batches are requested.
    @MainActor
    func testHitomiDetailKeepsMainGalleryInfoAfterLoadingManyRelatedGalleries() async throws {
        let galleryID = 4_037_854
        let relatedIDs = Array(4_037_855...4_037_863)
        let galleryInfos = Dictionary(uniqueKeysWithValues: relatedIDs.map { relatedID in
            (relatedID, Self.hitomiGalleryInfoJSON(id: relatedID, title: "Related \(relatedID)"))
        }).merging([
            galleryID: Self.hitomiGalleryInfoJSON(
                id: galleryID,
                title: "Main Gallery",
                fileCount: 2,
                relatedIDs: relatedIDs
            )
        ]) { current, _ in current }
        let client = HitomiMockHTTPClient(indexVersion: "1783485646", galleryInfos: galleryInfos)
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }
        let galleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(galleryID).html"))

        _ = try await dataSource.galleryDetail(from: galleryURL)
        let pageLinks = try await dataSource.galleryPageLinks(from: galleryURL, startPage: 2, limit: 1)

        XCTAssertEqual(pageLinks.map(\.pageNumber), [2])
        XCTAssertEqual(client.requestedGalleryInfoIDs.filter { $0 == galleryID }.count, 1)
    }

    /// Confirms cancelling related gallery loading stops the remaining gallery info requests.
    @MainActor
    func testHitomiCancellationStopsRemainingGalleryInfoBatchRequests() async throws {
        let galleryID = 4_037_854
        let relatedIDs = Array(4_037_855...4_037_858)
        let galleryInfos = Dictionary(uniqueKeysWithValues: relatedIDs.map { relatedID in
            (relatedID, Self.hitomiGalleryInfoJSON(id: relatedID, title: "Related \(relatedID)"))
        }).merging([
            galleryID: Self.hitomiGalleryInfoJSON(
                id: galleryID,
                title: "Main Gallery",
                relatedIDs: relatedIDs
            )
        ]) { current, _ in current }
        let client = HitomiMockHTTPClient(
            indexVersion: "1783485646",
            galleryInfos: galleryInfos,
            galleryInfoDelayNanoseconds: 50_000_000
        )
        let dataSource = HitomiDataSource(client: client) { _, _ in Data() }
        let galleryURL = try XCTUnwrap(URL(string: "https://hitomi.la/galleries/\(galleryID).html"))
        let task = Task { @MainActor in
            try await dataSource.galleryDetail(from: galleryURL)
        }
        let deadline = Date().addingTimeInterval(1)
        while client.requestedGalleryInfoIDs.count < 2, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(client.requestedGalleryInfoIDs.count, 2)

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected gallery detail cancellation.")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected cancellation error: \(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(client.requestedGalleryInfoIDs.count, 2)
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
        XCTAssertEqual(AppCopy.commonCopy, "复制")
        XCTAssertEqual(AppCopy.readerJumpPageTitle, "跳到页码")
        XCTAssertEqual(AppCopy.readerJumpPageConfirm, "跳转")
        XCTAssertEqual(AppCopy.readerImageLoadFailed, "图片加载失败")
        XCTAssertEqual(AppCopy.readerImageRetry, "重新加载图片")
        XCTAssertEqual(AppCopy.readerSaveImageTitle, "保存图片到相册？")
        XCTAssertEqual(PhotoLibraryImageSaveError.denied.localizedDescription, "没有相册写入权限。")
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

    /// Confirms custom cache notes survive later gallery metadata refreshes.
    @MainActor
    func testImageCacheStorePreservesGalleryNote() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 100, token: "abcdef1234")
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Original Gallery",
            japaneseTitle: nil,
            category: "Manga",
            coverURL: nil,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [],
            thumbnailPageURLs: [],
            pageCount: 1
        )

        store.saveGalleryMetadata(detail: detail)
        store.save(
            Data([0x01, 0x02]),
            for: URL(string: "https://example.test/page-1.webp")!,
            responseURL: URL(string: "https://example.test/page-1.webp")!,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Original Gallery",
                pageNumber: 1,
                pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!,
                totalPageCount: 1,
                thumbnailURL: nil
            )
        )
        store.setGalleryNote("Short note", for: identifier)
        store.saveGalleryMetadata(detail: detail)

        XCTAssertEqual(store.note(for: identifier), "Short note")
        XCTAssertEqual(store.gallerySummaries.first?.note, "Short note")
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


    /// Confirms AVIF bytes are decoded through ImageIO for Hitomi image URLs.
    func testImageDataRendererCanRenderAVIF() throws {
        let data = try makeAVIFData()

        let image = ImageDataRenderer.uiImage(from: data, allowsAnimation: true)
        let preview = ImageDataRenderer.uiImage(from: data, allowsAnimation: false, maxPixelSize: 16)

        XCTAssertNotNil(image)
        XCTAssertNotNil(preview)
    }

    /// Confirms legacy Hitomi thumbnail URLs move to the current CDN host.
    func testHitomiLegacyThumbnailURLMigratesToCurrentHost() {
        let legacyURL = URL(string: "https://bb.hitomi.la/webpsmalltn/8/9a/326d9.webp")!
        let currentURL = HitomiImageURLMigration.currentURL(for: legacyURL)

        XCTAssertEqual(currentURL.absoluteString, "https://tn.gold-usergeneratedcontent.net/webpsmalltn/8/9a/326d9.webp")
    }

    /// Confirms old and current Hitomi thumbnail URLs share one image cache entry.
    @MainActor
    func testImageCacheStoreSharesHitomiMigratedThumbnailAliases() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = ImageCacheStore(directoryURL: directoryURL)
        let legacyURL = URL(string: "https://bb.hitomi.la/webpsmalltn/8/9a/326d9.webp")!
        let currentURL = URL(string: "https://tn.gold-usergeneratedcontent.net/webpsmalltn/8/9a/326d9.webp")!
        let imageData = Data([0x01, 0x02, 0x03])

        store.save(imageData, for: currentURL)

        XCTAssertEqual(store.data(for: legacyURL), imageData)
        XCTAssertTrue(store.containsData(for: legacyURL))
    }

    /// Confirms a full clear invalidates an async save that already wrote its bytes.
    @MainActor
    func testImageCacheClearPreventsSuspendedSaveFromRestoringCache() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let gate = ImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await gate.suspend() }
        )
        let imageURL = URL(string: "https://example.test/suspended-clear.webp")!
        let saveTask = Task {
            await store.saveAsync(
                Data([0x01, 0x02, 0x03]),
                for: imageURL,
                responseURL: imageURL,
                context: nil
            )
        }

        await gate.waitUntilSuspended()
        store.clear()
        await gate.resume()
        await saveTask.value

        XCTAssertNil(store.data(for: imageURL))
        XCTAssertEqual(store.snapshot, .empty)
    }

    /// Confirms clearing one gallery invalidates only that gallery's suspended save.
    @MainActor
    func testImageCacheGalleryClearPreventsSuspendedSaveFromRestoringGallery() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let gate = ImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await gate.suspend() }
        )
        let identifier = EHGalleryIdentifier(gid: 710, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/suspended-gallery-clear.webp")!
        let saveTask = Task {
            await store.saveAsync(
                Data([0x04, 0x05, 0x06]),
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: identifier,
                    galleryTitle: "Suspended Gallery",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/710-1")!,
                    totalPageCount: 1,
                    thumbnailURL: nil
                )
            )
        }

        await gate.waitUntilSuspended()
        store.clearGallery(identifier)
        await gate.resume()
        await saveTask.value

        XCTAssertNil(store.data(for: imageURL))
        XCTAssertNil(store.gallerySummary(for: identifier))
        XCTAssertEqual(store.snapshot, .empty)
    }

    /// Confirms a replacement save overwrites bytes owned by a stale suspended save after a clear.
    @MainActor
    func testImageCacheGalleryClearAllowsReplacementSaveToOverwriteStaleBytes() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let gate = SelectiveImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await gate.suspendFirstInvocation() }
        )
        let identifier = EHGalleryIdentifier(gid: 711, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/replacement-gallery-clear.webp")!
        let context = ImageCacheContext(
            galleryIdentifier: identifier,
            galleryTitle: "Replacement Gallery",
            pageNumber: 1,
            pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/711-1")!,
            totalPageCount: 1,
            thumbnailURL: nil
        )
        let staleTask = Task {
            await store.saveAsync(
                Data([0x01, 0x02, 0x03]),
                for: imageURL,
                responseURL: imageURL,
                context: context
            )
        }

        await gate.waitUntilFirstInvocationSuspends()
        store.clearGallery(identifier)
        await store.saveAsync(
            Data([0x09, 0x08, 0x07]),
            for: imageURL,
            responseURL: imageURL,
            context: context
        )
        await gate.resumeFirstInvocation()
        await staleTask.value

        XCTAssertEqual(store.data(for: imageURL), Data([0x09, 0x08, 0x07]))
        XCTAssertEqual(store.gallerySummary(for: identifier)?.cachedPageCount, 1)
    }

    /// Confirms the newest same-key save owns bytes, page records, and digest reuse.
    @MainActor
    func testImageCacheNewestSameKeySaveRejectsOlderLateCommit() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let gate = SelectiveImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await gate.suspendFirstInvocation() }
        )
        let identifier = EHGalleryIdentifier(gid: 712, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/same-key-race.webp")!
        let olderData = Data([0x01, 0x02, 0x03])
        let newerData = Data([0x09, 0x08, 0x07])
        let olderTask = Task {
            await store.saveAsync(
                olderData,
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: identifier,
                    galleryTitle: "Same Key Gallery",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/712-1")!,
                    totalPageCount: 2,
                    thumbnailURL: nil
                )
            )
        }

        await gate.waitUntilFirstInvocationSuspends()
        await store.saveAsync(
            newerData,
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Same Key Gallery",
                pageNumber: 2,
                pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/712-2")!,
                totalPageCount: 2,
                thumbnailURL: nil
            )
        )
        await gate.resumeFirstInvocation()
        await olderTask.value

        XCTAssertEqual(store.data(for: imageURL), newerData)
        XCTAssertNil(store.pageRecord(for: identifier, pageNumber: 1))
        XCTAssertEqual(store.pageRecord(for: identifier, pageNumber: 2)?.imageURL, imageURL)

        let olderAliasURL = URL(string: "https://example.test/same-key-older-content.webp")!
        await store.saveAsync(
            olderData,
            for: olderAliasURL,
            responseURL: olderAliasURL,
            context: nil
        )

        XCTAssertEqual(store.data(for: imageURL), newerData)
        XCTAssertEqual(store.data(for: olderAliasURL), olderData)
    }

    /// Confirms synchronous replacement keeps file bytes and digest reuse aligned.
    @MainActor
    func testImageCacheSynchronousSameURLReplacementUpdatesBytesAndDigest() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let store = ImageCacheStore(directoryURL: directoryURL)
        let imageURL = URL(string: "https://example.test/synchronous-replacement.webp")!
        let duplicateURL = URL(string: "https://example.test/synchronous-duplicate.webp")!
        let originalData = Data([0x01, 0x02, 0x03])
        let replacementData = Data([0x09, 0x08, 0x07])

        store.save(originalData, for: imageURL)
        store.save(replacementData, for: imageURL)
        store.save(replacementData, for: duplicateURL)

        XCTAssertEqual(store.data(for: imageURL), replacementData)
        XCTAssertEqual(store.data(for: duplicateURL), replacementData)
    }

    /// Confirms an older successful write can commit after a newer same-key write fails.
    @MainActor
    func testImageCacheNewerSameKeyFailureRestoresOlderSuccessfulOwner() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let writeGate = SelectiveImageCacheWriteGate()
        let writeFailure = SelectiveImageCacheDataWriteFailure(failingInvocation: 2)
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await writeGate.suspendFirstInvocation() },
            beforeCacheDataWrite: { try writeFailure.throwIfNeeded() },
            cacheWriteErrorHandler: { _ in }
        )
        let identifier = EHGalleryIdentifier(gid: 714, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/newer-write-failure.webp")!
        let olderData = Data([0x01, 0x02, 0x03])
        let olderTask = Task {
            await store.saveAsync(
                olderData,
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: identifier,
                    galleryTitle: "Write Failure Gallery",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/714-1")!,
                    totalPageCount: 2,
                    thumbnailURL: nil
                )
            )
        }

        await writeGate.waitUntilFirstInvocationSuspends()
        await store.saveAsync(
            Data([0x09, 0x08, 0x07]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Write Failure Gallery",
                pageNumber: 2,
                pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/714-2")!,
                totalPageCount: 2,
                thumbnailURL: nil
            )
        )
        await writeGate.resumeFirstInvocation()
        await olderTask.value

        XCTAssertEqual(store.data(for: imageURL), olderData)
        XCTAssertEqual(store.pageRecord(for: identifier, pageNumber: 1)?.imageURL, imageURL)
        XCTAssertNil(store.pageRecord(for: identifier, pageNumber: 2))
    }

    /// Confirms clearing one gallery preserves a pending same-key write for another gallery.
    @MainActor
    func testImageCacheGalleryClearPreservesOtherScopePendingSameKeyWrite() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let writeGate = SelectiveImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await writeGate.suspendFirstInvocation() }
        )
        let firstIdentifier = EHGalleryIdentifier(gid: 715, token: "abcdef1234")
        let secondIdentifier = EHGalleryIdentifier(gid: 716, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/cross-scope-same-key.webp")!
        store.save(
            Data([0x01, 0x02, 0x03]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: firstIdentifier,
                galleryTitle: "First Gallery",
                pageNumber: 1,
                pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/715-1")!,
                totalPageCount: 1,
                thumbnailURL: nil
            )
        )
        let replacementData = Data([0x09, 0x08, 0x07])
        let replacementTask = Task {
            await store.saveAsync(
                replacementData,
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: secondIdentifier,
                    galleryTitle: "Second Gallery",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/716-1")!,
                    totalPageCount: 1,
                    thumbnailURL: nil
                )
            )
        }

        await writeGate.waitUntilFirstInvocationSuspends()
        store.clearGallery(firstIdentifier)
        await writeGate.resumeFirstInvocation()
        await replacementTask.value

        XCTAssertNil(store.pageRecord(for: firstIdentifier, pageNumber: 1))
        XCTAssertEqual(store.pageRecord(for: secondIdentifier, pageNumber: 1)?.imageURL, imageURL)
        XCTAssertEqual(store.data(for: imageURL), replacementData)
    }

    /// Confirms a stale replacement reconciles existing shared references to physical bytes.
    @MainActor
    func testImageCacheStaleReplacementReconcilesExistingSameKeyReferences() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let writeGate = SelectiveImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await writeGate.suspendFirstInvocation() }
        )
        let firstIdentifier = EHGalleryIdentifier(gid: 717, token: "abcdef1234")
        let staleIdentifier = EHGalleryIdentifier(gid: 718, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/stale-shared-replacement.webp")!
        let originalData = Data([0x01, 0x02])
        let replacementData = Data([0x09, 0x08, 0x07, 0x06, 0x05])
        store.save(
            originalData,
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: firstIdentifier,
                galleryTitle: "Existing Gallery",
                pageNumber: 1,
                pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/717-1")!,
                totalPageCount: 1,
                thumbnailURL: nil
            )
        )
        let staleTask = Task {
            await store.saveAsync(
                replacementData,
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: staleIdentifier,
                    galleryTitle: "Stale Gallery",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/718-1")!,
                    totalPageCount: 1,
                    thumbnailURL: nil
                )
            )
        }

        await writeGate.waitUntilFirstInvocationSuspends()
        store.clearGallery(staleIdentifier)
        await writeGate.resumeFirstInvocation()
        await staleTask.value

        XCTAssertEqual(store.data(for: imageURL), replacementData)
        XCTAssertEqual(
            store.pageRecord(for: firstIdentifier, pageNumber: 1)?.byteCount,
            Int64(replacementData.count)
        )
        XCTAssertNil(store.pageRecord(for: staleIdentifier, pageNumber: 1))

        let originalAliasURL = URL(string: "https://example.test/stale-original-content.webp")!
        store.save(originalData, for: originalAliasURL)
        XCTAssertEqual(store.data(for: originalAliasURL), originalData)
    }

    /// Confirms stale gallery replacement preserves an alias-only cache owner.
    @MainActor
    func testImageCacheStaleReplacementPreservesNonGalleryAlias() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let writeGate = SelectiveImageCacheWriteGate()
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await writeGate.suspendFirstInvocation() }
        )
        let staleIdentifier = EHGalleryIdentifier(gid: 719, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/stale-alias-replacement.webp")!
        let originalData = Data([0x01, 0x02])
        let replacementData = Data([0x09, 0x08, 0x07, 0x06])
        store.save(originalData, for: imageURL)

        let staleTask = Task {
            await store.saveAsync(
                replacementData,
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: staleIdentifier,
                    galleryTitle: "Stale Alias Gallery",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/719-1")!,
                    totalPageCount: 1,
                    thumbnailURL: nil
                )
            )
        }

        await writeGate.waitUntilFirstInvocationSuspends()
        store.clearGallery(staleIdentifier)
        await writeGate.resumeFirstInvocation()
        await staleTask.value

        XCTAssertEqual(store.data(for: imageURL), replacementData)
        XCTAssertEqual(store.snapshot.fileCount, 1)
        XCTAssertEqual(store.snapshot.byteCount, Int64(replacementData.count))
        XCTAssertNil(store.pageRecord(for: staleIdentifier, pageNumber: 1))

        let originalAliasURL = URL(string: "https://example.test/stale-alias-original.webp")!
        store.save(originalData, for: originalAliasURL)
        XCTAssertEqual(store.data(for: imageURL), replacementData)
        XCTAssertEqual(store.data(for: originalAliasURL), originalData)
    }

    /// Confirms a failed newer owner cleans stale bytes that no valid reference retained.
    @MainActor
    func testImageCacheFailedNewerOwnerCleansUnreferencedStaleBytes() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let writeGate = SelectiveImageCacheWriteGate()
        let diskGate = ImageCacheDiskMutationGate()
        let writeFailure = SelectiveImageCacheDataWriteFailure(failingInvocation: 2)
        let store = ImageCacheStore(
            directoryURL: directoryURL,
            afterCacheFileWrite: { await writeGate.suspendFirstInvocation() },
            beforeCacheDiskMutation: { diskGate.suspendNextMutationIfArmed() },
            beforeCacheDataWrite: { try writeFailure.throwIfNeeded() },
            cacheWriteErrorHandler: { _ in }
        )
        let staleIdentifier = EHGalleryIdentifier(gid: 720, token: "abcdef1234")
        let newerIdentifier = EHGalleryIdentifier(gid: 721, token: "abcdef1234")
        let imageURL = URL(string: "https://example.test/stale-then-failed-owner.webp")!
        let staleTask = Task {
            await store.saveAsync(
                Data([0x01, 0x02, 0x03]),
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: staleIdentifier,
                    galleryTitle: "Stale Owner",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/720-1")!,
                    totalPageCount: 1,
                    thumbnailURL: nil
                )
            )
        }

        await writeGate.waitUntilFirstInvocationSuspends()
        store.clearGallery(staleIdentifier)
        diskGate.armNextMutation()
        let failingTask = Task {
            await store.saveAsync(
                Data([0x09, 0x08, 0x07]),
                for: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: newerIdentifier,
                    galleryTitle: "Failed Owner",
                    pageNumber: 1,
                    pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/721-1")!,
                    totalPageCount: 1,
                    thumbnailURL: nil
                )
            )
        }

        await diskGate.waitUntilSuspended()
        await writeGate.resumeFirstInvocation()
        await staleTask.value
        diskGate.resume()
        await failingTask.value

        XCTAssertFalse(store.hasNonGalleryImageCache)
        XCTAssertNil(store.pageRecord(for: staleIdentifier, pageNumber: 1))
        XCTAssertNil(store.pageRecord(for: newerIdentifier, pageNumber: 1))
        XCTAssertEqual(store.snapshot, .empty)
    }

    /// Confirms a save queued behind gallery cleanup rechecks file existence before writing.
    @MainActor
    func testImageCacheSaveQueuedBehindAsyncRemovalRestoresBackingFile() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appending(
            path: "ImageCacheRemovalRace-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let rootURL = baseURL.appending(path: "Cached Gallery", directoryHint: .isDirectory)
        let stagingURL = baseURL.appending(path: "Staging", directoryHint: .isDirectory)
        let cacheURL = baseURL.appending(path: "Cache", directoryHint: .isDirectory)
        let diskGate = ImageCacheDiskMutationGate()
        let enqueueGate = ImageCacheEnqueueGate()
        let persistentStore = CachedGalleryStore(rootURL: rootURL, stagingRootURL: stagingURL)
        let store = ImageCacheStore(
            directoryURL: cacheURL,
            persistentGalleryStore: persistentStore,
            afterCacheDataWriteEnqueued: {
                await enqueueGate.signal()
            },
            beforeCacheDiskMutation: {
                diskGate.suspendNextMutationIfArmed()
            }
        )
        let identifier = EHGalleryIdentifier(gid: 713, token: "abcdef1234")
        let pageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/713-1")!
        let imageURL = URL(string: "https://example.test/removal-race.webp")!
        let context = ImageCacheContext(
            galleryIdentifier: identifier,
            galleryTitle: "Removal Race Gallery",
            pageNumber: 1,
            pageURL: pageURL,
            totalPageCount: 1,
            thumbnailURL: nil
        )
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Removal Race Gallery",
            japaneseTitle: nil,
            category: "Manga",
            coverURL: nil,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [EHGalleryPageLink(pageNumber: 1, pageURL: pageURL)],
            thumbnailPageURLs: [],
            pageCount: 1
        )
        store.save(Data([0x01, 0x02, 0x03]), for: imageURL, responseURL: imageURL, context: context)
        try await store.preparePersistentDownload(detail: detail, fallback: nil)
        XCTAssertTrue(persistentStore.hasCompleteStagedGallery(identifier))

        diskGate.armNextMutation()
        let finalizationTask = Task {
            try await store.finalizePersistentDownload(identifier)
        }
        await diskGate.waitUntilSuspended()
        let replacementData = Data([0x09, 0x08, 0x07])
        let replacementTask = Task {
            await store.saveAsync(
                replacementData,
                for: imageURL,
                responseURL: imageURL,
                context: context
            )
        }
        await enqueueGate.waitUntilSignaled()
        diskGate.resume()
        try await finalizationTask.value
        await replacementTask.value

        let reloadedStore = ImageCacheStore(directoryURL: cacheURL)
        XCTAssertEqual(reloadedStore.data(for: imageURL), replacementData)
        XCTAssertEqual(reloadedStore.pageRecord(for: identifier, pageNumber: 1)?.imageURL, imageURL)
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

    /// Confirms cross-screen author searches select the search tab and can be consumed once.
    @MainActor
    func testAppNavigationStoreOpensAndConsumesSearchRequest() throws {
        let store = AppNavigationStore()
        let previousNavigationID = store.searchNavigationID
        store.selectedTab = .library

        store.openSearch(query: "demo", site: .hitomi)

        let request = try XCTUnwrap(store.searchRequest)
        XCTAssertEqual(store.selectedTab, .search)
        XCTAssertNotEqual(store.searchNavigationID, previousNavigationID)
        XCTAssertEqual(request.query, "demo")
        XCTAssertEqual(request.site, .hitomi)

        store.consumeSearchRequest(id: request.id)
        XCTAssertNil(store.searchRequest)
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

    /// Confirms gallery author taps use each site's expected artist query syntax.
    func testArtistSearchQueryUsesSiteSyntax() {
        XCTAssertEqual(ContentSite.hitomi.artistSearchQuery(for: "ssa"), "artist:ssa")
        XCTAssertEqual(ContentSite.eHentai.artistSearchQuery(for: "ssa"), "artist:\"ssa$\"")
    }

    /// Builds a tiny AVIF image for decoder tests.
    private func makeAVIFData() throws -> Data {
        let data = NSMutableData()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(UIColor.systemPurple.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.avif" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

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

    /// Builds minimal Hitomi galleryinfo JSON for search tests.
    private static func hitomiGalleryInfoJSON(
        id: Int,
        title: String,
        hash: String = "abcdef1234567890",
        hasAVIF: Bool = false,
        fileCount: Int = 1,
        groups: [String] = [],
        characters: [String] = [],
        relatedIDs: [Int] = []
    ) -> String {
        let files = (0..<fileCount).map { index in
            let fileHash = index == 0 ? hash : String(format: "%016x", id * 1_000 + index)
            return #"{"name":"\#(index + 1).jpg","hash":"\#(fileHash)","haswebp":1,"hasavif":\#(hasAVIF ? 1 : 0)}"#
        }
        let groupsJSON = groups.isEmpty ? "" : #","groups":[\#(groups.map { #"{"group":"\#($0)"}"# }.joined(separator: ","))]"#
        let charactersJSON = characters.isEmpty ? "" : #","characters":[\#(characters.map { #"{"character":"\#($0)"}"# }.joined(separator: ","))]"#
        let relatedJSON = relatedIDs.isEmpty ? "" : #","related":[\#(relatedIDs.map(String.init).joined(separator: ","))]"#
        return """
        {"id":"\(id)","title":"\(title)","type":"doujinshi","language":"english","files":[\(files.joined(separator: ","))]\(groupsJSON)\(charactersJSON)\(relatedJSON)}
        """
    }


    /// Builds a minimal gg.js image context for Hitomi URL tests.
    fileprivate static func hitomiImageContextScript(pathPrefix: String, suffixValue: Int, codes: [Int]) -> String {
        let cases = codes.map { "case \($0):" }.joined(separator: "\n")
        return """
        'use strict';
        gg = { b: 'stale-prefix/', m: function(g) {
        var o = \(suffixValue);
        switch (g) {
        \(cases)
        o = 0; break;
        }
        return o;
        },
        s: function(h) { return h; },
        b: '\(pathPrefix)'
        };
        """
    }
}

private struct HitomiSearchMockData {
    let query: String
    let galleryIDs: [Int]
    var frontPageIDs: [Int] = []
    private let dataOffset: UInt64 = 512

    /// Returns fixture bytes for Hitomi range requests.
    func data(for url: URL, range: ClosedRange<UInt64>) throws -> Data {
        if url.path == "/n/index-all.nozomi" {
            return rangedData(nozomiData(for: frontPageIDs), range: range)
        }
        if url.path.hasSuffix(".index") {
            return paddedIndexNode()
        }
        if url.path.hasSuffix(".data") {
            return rangedData(galleryDataFile(), range: range)
        }
        throw EHNetworkError.invalidResponse
    }

    /// Builds a single root node containing the query hash and one data range.
    private func paddedIndexNode() -> Data {
        var data = Data()
        appendInt32(1, to: &data)
        appendInt32(4, to: &data)
        data.append(Data(SHA256.hash(data: Data(query.utf8)).prefix(4)))
        appendInt32(1, to: &data)
        appendUInt64(dataOffset, to: &data)
        appendInt32(Int32(galleryData().count), to: &data)
        for _ in 0..<17 {
            appendUInt64(0, to: &data)
        }
        if data.count < 464 {
            data.append(contentsOf: repeatElement(0, count: 464 - data.count))
        }
        return data
    }

    /// Builds the full galleries data file with padding before the searched range.
    private func galleryDataFile() -> Data {
        var data = Data(repeating: 0, count: Int(dataOffset))
        data.append(galleryData())
        return data
    }

    /// Builds the gallery id data payload referenced by the B-tree node.
    private func galleryData() -> Data {
        var data = Data()
        appendInt32(Int32(galleryIDs.count), to: &data)
        data.append(nozomiData(for: galleryIDs))
        return data
    }

    /// Builds a big-endian nozomi payload for gallery ids.
    private func nozomiData(for galleryIDs: [Int]) -> Data {
        var data = Data()
        for galleryID in galleryIDs {
            appendInt32(Int32(galleryID), to: &data)
        }
        return data
    }

    /// Returns an inclusive byte range from fixture data.
    private func rangedData(_ data: Data, range: ClosedRange<UInt64>) -> Data {
        let startIndex = min(Int(range.lowerBound), data.count)
        let endIndex = min(Int(range.upperBound) + 1, data.count)
        guard startIndex < endIndex else { return Data() }
        return data[startIndex..<endIndex]
    }

    /// Appends one big-endian 32-bit integer.
    private func appendInt32(_ value: Int32, to data: inout Data) {
        let unsigned = UInt32(bitPattern: value)
        data.append(UInt8((unsigned >> 24) & 0xff))
        data.append(UInt8((unsigned >> 16) & 0xff))
        data.append(UInt8((unsigned >> 8) & 0xff))
        data.append(UInt8(unsigned & 0xff))
    }

    /// Appends one big-endian 64-bit integer.
    private func appendUInt64(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }
}

@MainActor
private final class HitomiMockHTTPClient: EHDataHTTPClient {
    private let indexVersion: String
    private let galleryInfos: [Int: String]
    private let imageContextScript: String
    private let nozomiGalleryIDsByPath: [String: [Int]]
    private let galleryInfoDelayNanoseconds: UInt64
    private var galleryInfoFailuresRemainingByID: [Int: Int]
    private(set) var requestedGalleryInfoIDs: [Int] = []
    private(set) var requestedDataPaths: [String] = []

    /// Creates a mock Hitomi client for version, image context, and gallery info requests.
    init(
        indexVersion: String,
        galleryInfos: [Int: String],
        imageContextScript: String = MyEHViewerTests.hitomiImageContextScript(pathPrefix: "galleries/", suffixValue: 1, codes: []),
        nozomiGalleryIDsByPath: [String: [Int]] = [:],
        galleryInfoDelayNanoseconds: UInt64 = 0,
        galleryInfoFailuresRemainingByID: [Int: Int] = [:]
    ) {
        self.indexVersion = indexVersion
        self.galleryInfos = galleryInfos
        self.imageContextScript = imageContextScript
        self.nozomiGalleryIDsByPath = nozomiGalleryIDsByPath
        self.galleryInfoDelayNanoseconds = galleryInfoDelayNanoseconds
        self.galleryInfoFailuresRemainingByID = galleryInfoFailuresRemainingByID
    }

    /// Returns the search index version, image context, or one gallery info script.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        if url.path == "/galleriesindex/version" {
            return EHHTTPResponse(url: url, statusCode: 200, body: indexVersion)
        }
        if url.path == "/gg.js" {
            return EHHTTPResponse(url: url, statusCode: 200, body: imageContextScript)
        }
        if let galleryID = galleryID(from: url) {
            requestedGalleryInfoIDs.append(galleryID)
            if galleryInfoDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: galleryInfoDelayNanoseconds)
            }
            if let remainingFailureCount = galleryInfoFailuresRemainingByID[galleryID], remainingFailureCount > 0 {
                galleryInfoFailuresRemainingByID[galleryID] = remainingFailureCount - 1
                throw EHNetworkError.invalidResponse
            }
            guard let body = galleryInfos[galleryID] else {
                throw EHNetworkError.unacceptableStatusCode(404)
            }
            return EHHTTPResponse(url: url, statusCode: 200, body: "var galleryinfo = \(body);")
        }
        throw EHNetworkError.unacceptableStatusCode(404)
    }

    /// Returns empty data for unused data requests.
    func data(_ url: URL) async throws -> EHDataResponse {
        let path = url.path.removingPercentEncoding ?? url.path
        requestedDataPaths.append(path)
        if let galleryIDs = nozomiGalleryIDsByPath[path] {
            return EHDataResponse(url: url, statusCode: 200, data: Self.nozomiData(for: galleryIDs))
        }
        return EHDataResponse(url: url, statusCode: 200, data: Data())
    }

    /// Returns empty data for unused referer-aware data requests.
    func data(_ url: URL, referer: URL?) async throws -> EHDataResponse {
        try await data(url)
    }

    /// Extracts a gallery id from `/galleries/<id>.js`.
    private func galleryID(from url: URL) -> Int? {
        guard let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"^/galleries/([0-9]+)\.js$"#), match.count >= 2 else {
            return nil
        }
        return Int(match[1])
    }

    /// Builds a big-endian nozomi payload for mocked namespace searches.
    private static func nozomiData(for galleryIDs: [Int]) -> Data {
        var data = Data()
        for galleryID in galleryIDs {
            appendInt32(Int32(galleryID), to: &data)
        }
        return data
    }

    /// Appends one big-endian 32-bit integer.
    private static func appendInt32(_ value: Int32, to data: inout Data) {
        let unsigned = UInt32(bitPattern: value)
        data.append(UInt8((unsigned >> 24) & 0xff))
        data.append(UInt8((unsigned >> 16) & 0xff))
        data.append(UInt8((unsigned >> 8) & 0xff))
        data.append(UInt8(unsigned & 0xff))
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

    /// Confirms completed page tasks enqueue later pages while an earlier page is still slow.
    func testDownloadStartsNextMissingPageWhenAnyPageFinishes() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 109, token: "abcdef1234")
        let firstPageURL = URL(string: "https://e-hentai.org/s/slowfirst/109-1")!
        let secondPageURL = URL(string: "https://e-hentai.org/s/fastsecond/109-2")!
        let thirdPageURL = URL(string: "https://e-hentai.org/s/queuedthird/109-3")!
        let firstImageURL = URL(string: "https://example.test/109-1.webp")!
        let secondImageURL = URL(string: "https://example.test/109-2.webp")!
        let thirdImageURL = URL(string: "https://example.test/109-3.webp")!
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: [
                firstPageURL: Self.imagePageHTML(pageNumber: 1, imageURL: firstImageURL),
                secondPageURL: Self.imagePageHTML(pageNumber: 2, imageURL: secondImageURL),
                thirdPageURL: Self.imagePageHTML(pageNumber: 3, imageURL: thirdImageURL)
            ],
            dataResponses: [
                firstImageURL: .success(Data([0x01])),
                secondImageURL: .success(Data([0x02])),
                thirdImageURL: .success(Data([0x03]))
            ],
            dataDelays: [firstImageURL: 250_000_000]
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentPagesPerGallery: 2,
            retryDelayRange: 0...0
        )
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Slow First Page Gallery",
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
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(client.dataRequestCount(for: thirdImageURL), 1)

        await waitForFinishedDownload(manager: manager, identifier: identifier)
        XCTAssertEqual(cacheStore.gallerySummaries.first?.cachedPageCount, 3)
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

    /// Confirms image downloads use the reader page as their referer.
    func testDownloadUsesReaderPageRefererForImages() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 104, token: "abcdef1234")
        let pageURL = URL(string: "https://e-hentai.org/s/refererpage/104-1")!
        let imageURL = URL(string: "https://example.test/referer.webp")!
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: [
                pageURL: Self.imagePageHTML(pageNumber: 1, imageURL: imageURL, galleryID: 104)
            ],
            dataResponses: [
                imageURL: .success(Data([0x04]))
            ]
        )
        let manager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Referer Gallery",
            japaneseTitle: nil,
            category: "Manga",
            coverURL: nil,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [
                EHGalleryPageLink(pageNumber: 1, pageURL: pageURL)
            ],
            thumbnailPageURLs: [],
            pageCount: 1
        )

        manager.startDownload(detail: detail)
        await waitForFinishedDownload(manager: manager, identifier: identifier)

        XCTAssertEqual(client.imageReferer(for: imageURL), pageURL)
        XCTAssertEqual(cacheStore.data(for: imageURL), Data([0x04]))
    }

    /// Confirms a 404 page marks the gallery so later bulk resumes skip it.
    func testDownloadMarksNotFoundPageAndSkipsFutureBulkResume() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 102, token: "abcdef1234")
        let firstPageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/102-1")!
        let secondPageURL = URL(string: "https://e-hentai.org/s/ddddeeeeff/102-2")!
        let thirdPageURL = URL(string: "https://e-hentai.org/s/eeeeffffgg/102-3")!
        let firstImageURL = URL(string: "https://example.test/102-1.webp")!
        let secondImageURL = URL(string: "https://example.test/102-2.webp")!
        let thirdImageURL = URL(string: "https://example.test/102-3.webp")!
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: [
                firstPageURL: Self.imagePageHTML(pageNumber: 1, imageURL: firstImageURL),
                secondPageURL: Self.imagePageHTML(pageNumber: 2, imageURL: secondImageURL),
                thirdPageURL: Self.imagePageHTML(pageNumber: 3, imageURL: thirdImageURL)
            ],
            dataResponses: [
                firstImageURL: .success(Data([0x01])),
                secondImageURL: .failure(EHNetworkError.unacceptableStatusCode(404)),
                thirdImageURL: .success(Data([0x03]))
            ]
        )
        let manager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)
        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Not Found Page Gallery",
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
        XCTAssertEqual(progress.errorMessage, "第 2 页下载失败：服务器返回状态码 404。")
        XCTAssertEqual(client.dataRequestCount(for: secondImageURL), 1)
        XCTAssertEqual(cacheStore.gallerySummaries.first?.isDownloadUnavailable, true)

        let retryManager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)
        retryManager.startUnfinishedDownloads(from: cacheStore.gallerySummaries)

        XCTAssertNil(retryManager.aggregateProgress)
    }

    /// Confirms a cached gallery detail 404 is marked and skipped by later bulk resumes.
    func testCachedGalleryDetailNotFoundSkipsFutureBulkResume() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let identifier = EHGalleryIdentifier(gid: 103, token: "abcdef1234")
        let pageURL = URL(string: "https://e-hentai.org/s/aaaabbbbcc/103-1")!
        let imageURL = URL(string: "https://example.test/103-1.webp")!
        cacheStore.save(
            Data([0x01]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: identifier,
                galleryTitle: "Unavailable Detail Gallery",
                pageNumber: 1,
                pageURL: pageURL,
                totalPageCount: 2,
                thumbnailURL: nil
            )
        )
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: [:],
            dataResponses: [:],
            htmlErrors: [identifier.url(): EHNetworkError.unacceptableStatusCode(404)]
        )
        let manager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)

        manager.startUnfinishedDownloads(from: cacheStore.gallerySummaries)
        await waitForFinishedDownload(manager: manager, identifier: identifier)

        let progress = try XCTUnwrap(manager.progress(for: identifier))
        XCTAssertFalse(progress.isRunning)
        XCTAssertEqual(progress.downloadedPageCount, 1)
        XCTAssertEqual(progress.errorMessage, "服务器返回状态码 404。")
        XCTAssertEqual(cacheStore.gallerySummaries.first?.isDownloadUnavailable, true)

        let retryManager = GalleryDownloadManager(client: client, cacheStore: cacheStore, retryDelayRange: 0...0)
        retryManager.startUnfinishedDownloads(from: cacheStore.gallerySummaries)

        XCTAssertNil(retryManager.aggregateProgress)
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

    /// Confirms the injected global limit bounds page pipelines across galleries.
    func testDownloadLimitsGlobalPagePipelinesAcrossGalleries() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let fixtures = (401...403).map { Self.downloadFixture(galleryID: $0, pageCount: 2) }
        var htmlResponses: [URL: String] = [:]
        var dataResponses: [URL: Result<Data, Error>] = [:]
        for fixture in fixtures {
            htmlResponses.merge(fixture.htmlResponses) { _, incoming in incoming }
            dataResponses.merge(fixture.dataResponses) { _, incoming in incoming }
        }
        let imageURLs = fixtures.flatMap { $0.imageURLs }
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: htmlResponses,
            dataResponses: dataResponses,
            suspendedDataURLs: Set(imageURLs)
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentDownloads: 3,
            maxConcurrentPagesPerGallery: 2,
            maxConcurrentPageOperations: 4,
            retryDelayRange: 0...0
        )

        for fixture in fixtures {
            manager.startDownload(detail: fixture.detail)
        }

        let reachedGlobalLimit = await waitUntil(
            failureMessage: "Timed out waiting for four global page pipelines."
        ) {
            client.activeDataRequestCount == 4
        }
        guard reachedGlobalLimit else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }

        XCTAssertEqual(client.maxConcurrentDataRequestCount, 4)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.requestedDataURLs.count, 4)

        client.resumeAllDataRequests()
        let startedRemainingPages = await waitUntil(
            failureMessage: "Timed out waiting for the remaining page pipelines."
        ) {
            client.requestedDataURLs.count == imageURLs.count
        }
        guard startedRemainingPages else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }
        client.resumeAllDataRequests()

        for fixture in fixtures {
            await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)
        }
        for fixture in fixtures {
            XCTAssertEqual(manager.progress(for: fixture.detail.identifier)?.downloadedPageCount, 2)
        }
        XCTAssertEqual(client.maxConcurrentDataRequestCount, 4)
    }

    /// Confirms the global permit remains held while permanent page persistence is blocked.
    func testGlobalPageLimitIncludesPersistentCommitStage() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let commitGate = DownloadPersistenceGate(expectedArrivalCount: 4)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            beforePageCommit: { _ in
                await commitGate.suspendUntilOpened()
            }
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let fixtures = (410...412).map { Self.downloadFixture(galleryID: $0, pageCount: 2) }
        var htmlResponses: [URL: String] = [:]
        var dataResponses: [URL: Result<Data, Error>] = [:]
        for fixture in fixtures {
            htmlResponses.merge(fixture.htmlResponses) { _, incoming in incoming }
            dataResponses.merge(fixture.dataResponses) { _, incoming in incoming }
        }
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: htmlResponses,
            dataResponses: dataResponses
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentDownloads: 3,
            maxConcurrentPagesPerGallery: 2,
            maxConcurrentPageOperations: 4,
            retryDelayRange: 0...0
        )

        for fixture in fixtures {
            manager.startDownload(detail: fixture.detail)
        }
        await commitGate.waitUntilExpectedArrivals()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(client.requestedDataURLs.count, 4)
        await commitGate.open()
        for fixture in fixtures {
            await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)
            XCTAssertEqual(manager.progress(for: fixture.detail.identifier)?.downloadedPageCount, 2)
        }
    }

    /// Confirms a fast three-page download finalizes from local progress before the publish delay.
    func testFastPersistentDownloadFinalizesAllPagesBeforeProgressPublishWindow() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = Self.downloadFixture(galleryID: 406, pageCount: 3)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: fixture.htmlResponses,
            dataResponses: fixture.dataResponses
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentPagesPerGallery: 3,
            maxConcurrentPageOperations: 3,
            retryDelayRange: 0...0
        )
        let startedAt = Date()

        manager.startDownload(detail: fixture.detail)
        let finishedWithinPublishWindow = await waitUntil(
            timeout: 0.35,
            failureMessage: "Timed out waiting for the permanent download before the progress publish window."
        ) {
            manager.progress(for: fixture.detail.identifier)?.isRunning == false
        }
        guard finishedWithinPublishWindow else {
            manager.pauseAllDownloads()
            return
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.35)
        let progress = try XCTUnwrap(manager.progress(for: fixture.detail.identifier))
        XCTAssertEqual(progress.downloadedPageCount, 3)
        XCTAssertEqual(progress.totalPageCount, 3)
        XCTAssertNil(progress.errorMessage)
        for imageURL in fixture.imageURLs {
            XCTAssertEqual(client.dataRequestCount(for: imageURL), 1)
        }

        let stagedGalleryURL = environment.stagingURL.appending(
            path: fixture.detail.identifier.id,
            directoryHint: .isDirectory
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedGalleryURL.path))
        let finalFolders = try FileManager.default.contentsOfDirectory(
            at: environment.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(finalFolders.count, 1)
        let finalFolder = try XCTUnwrap(finalFolders.first)
        let manifestData = try Data(contentsOf: finalFolder.appending(path: "manifest.json"))
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData)
        let manifest = try XCTUnwrap(manifestObject as? [String: Any])
        let pages = try XCTUnwrap(manifest["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.compactMap { $0["pageNumber"] as? Int }.sorted(), [1, 2, 3])

        let reloadedStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        XCTAssertEqual(
            reloadedStore.summaries.first?.pageRecords.map(\.pageNumber),
            [1, 2, 3]
        )
    }

    /// Confirms a complete staged gallery can resume only to finish its folder move.
    func testCompleteStagingResumesFinalizationWithoutRedownloadingImages() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = Self.downloadFixture(galleryID: 413, pageCount: 1)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let imageURL = fixture.imageURLs[0]
        try await cacheStore.preparePersistentDownload(detail: fixture.detail, fallback: nil)
        try await cacheStore.saveDownloadedPageAsync(
            Data([0x41, 0x42, 0x43]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: fixture.detail.identifier,
                galleryTitle: fixture.detail.title,
                pageNumber: 1,
                pageURL: fixture.pageURLs[0],
                totalPageCount: 1,
                thumbnailURL: nil
            )
        )
        XCTAssertTrue(persistentStore.hasStagedGallery(fixture.detail.identifier))

        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: fixture.htmlResponses,
            dataResponses: fixture.dataResponses
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: fixture.detail)
        await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)

        XCTAssertEqual(client.dataRequestCount(for: imageURL), 0)
        XCTAssertFalse(persistentStore.hasStagedGallery(fixture.detail.identifier))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.stagingURL.appending(
                    path: fixture.detail.identifier.id,
                    directoryHint: .isDirectory
                ).path
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: environment.rootURL,
                includingPropertiesForKeys: nil
            ).count,
            1
        )
    }

    /// Confirms bulk resume includes a complete gallery that still lives in staging.
    func testBulkResumeQueuesCompleteStagingForFinalization() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = Self.downloadFixture(galleryID: 414, pageCount: 1)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let imageURL = fixture.imageURLs[0]
        try await cacheStore.preparePersistentDownload(detail: fixture.detail, fallback: nil)
        try await cacheStore.saveDownloadedPageAsync(
            Data([0x51, 0x52, 0x53]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: fixture.detail.identifier,
                galleryTitle: fixture.detail.title,
                pageNumber: 1,
                pageURL: fixture.pageURLs[0],
                totalPageCount: 1,
                thumbnailURL: nil
            )
        )
        await cacheStore.markGalleryDownloadUnavailable(
            fixture.detail.identifier,
            title: fixture.detail.title,
            totalPageCount: 1
        )
        let summary = try XCTUnwrap(cacheStore.gallerySummary(for: fixture.detail.identifier))
        XCTAssertTrue(summary.isDownloadUnavailable)
        XCTAssertTrue(summary.isStagedComplete)
        XCTAssertTrue(summary.needsDownloadResume)
        let client = GalleryDownloadMockHTTPClient(htmlResponses: [:], dataResponses: [:])
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            retryDelayRange: 0...0
        )

        manager.startUnfinishedDownloads(from: [summary])
        await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)

        XCTAssertEqual(client.htmlRequestCount(for: fixture.detail.identifier.url()), 0)
        XCTAssertEqual(client.requestedDataURLs, [])
        XCTAssertFalse(persistentStore.hasStagedGallery(fixture.detail.identifier))
        let progress = try XCTUnwrap(manager.progress(for: fixture.detail.identifier))
        XCTAssertEqual(progress.downloadedPageCount, 1)
        XCTAssertEqual(progress.totalPageCount, 1)
        XCTAssertNil(progress.errorMessage)
    }

    /// Confirms a complete disposable cache can still be promoted to permanent storage.
    func testCompleteCacheOnlyGalleryCanStartPermanentDownload() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = Self.downloadFixture(galleryID: 415, pageCount: 1)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let imageURL = fixture.imageURLs[0]
        cacheStore.save(
            Data([0x61, 0x62, 0x63]),
            for: imageURL,
            responseURL: imageURL,
            context: ImageCacheContext(
                galleryIdentifier: fixture.detail.identifier,
                galleryTitle: fixture.detail.title,
                pageNumber: 1,
                pageURL: fixture.pageURLs[0],
                totalPageCount: 1,
                thumbnailURL: nil
            )
        )
        XCTAssertEqual(
            cacheStore.gallerySummary(for: fixture.detail.identifier)?.storageState,
            .cacheOnly
        )
        let client = GalleryDownloadMockHTTPClient(htmlResponses: [:], dataResponses: [:])
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: fixture.detail)
        let didFinalize = await waitUntil(
            failureMessage: "Timed out promoting a complete cache-only gallery."
        ) {
            let summary = cacheStore.gallerySummary(for: fixture.detail.identifier)
            return summary?.storageState == .persistent && summary?.isStaged == false
        }

        XCTAssertTrue(didFinalize)
        XCTAssertEqual(client.requestedDataURLs, [])
        XCTAssertEqual(client.htmlRequestCount(for: fixture.pageURLs[0]), 0)
        XCTAssertFalse(persistentStore.hasStagedGallery(fixture.detail.identifier))
    }

    /// Confirms a finalized gallery can redownload a page removed through Files.
    func testCompletedPersistentGalleryWithMissingFileCanRestart() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = Self.downloadFixture(galleryID: 416, pageCount: 1)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: fixture.htmlResponses,
            dataResponses: fixture.dataResponses
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentPagesPerGallery: 1,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: fixture.detail)
        await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)
        let storedRecord = try XCTUnwrap(
            cacheStore.pageRecord(for: fixture.detail.identifier, pageNumber: 1)
        )
        let localFileURL = try XCTUnwrap(storedRecord.localFileURL)
        XCTAssertEqual(client.dataRequestCount(for: fixture.imageURLs[0]), 1)
        try FileManager.default.removeItem(at: localFileURL)

        manager.startDownload(detail: fixture.detail)
        await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)

        XCTAssertEqual(client.dataRequestCount(for: fixture.imageURLs[0]), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFileURL.path))
        XCTAssertFalse(persistentStore.hasStagedGallery(fixture.detail.identifier))
    }

    /// Confirms one completed permanent gallery publishes while another gallery keeps downloading.
    func testCompletedPersistentGalleryPublishesBeforeAnotherGalleryFinishesAndCannotRestart() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let completedFixture = Self.downloadFixture(galleryID: 408, pageCount: 1)
        let blockedFixture = Self.downloadFixture(galleryID: 409, pageCount: 1)
        var htmlResponses = blockedFixture.htmlResponses
        htmlResponses.merge(completedFixture.htmlResponses) { _, incoming in incoming }
        var dataResponses = blockedFixture.dataResponses
        dataResponses.merge(completedFixture.dataResponses) { _, incoming in incoming }
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let blockedImageURL = blockedFixture.imageURLs[0]
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: htmlResponses,
            dataResponses: dataResponses,
            suspendedDataURLs: [blockedImageURL]
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentDownloads: 2,
            maxConcurrentPagesPerGallery: 1,
            maxConcurrentPageOperations: 2,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: blockedFixture.detail)
        let blockedDownloadStarted = await waitUntil(
            failureMessage: "Timed out waiting for the blocked gallery request."
        ) {
            client.activeDataRequestCount == 1
                && client.dataRequestCount(for: blockedImageURL) == 1
        }
        guard blockedDownloadStarted else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }

        manager.startDownload(detail: completedFixture.detail)
        await waitForFinishedDownload(
            manager: manager,
            identifier: completedFixture.detail.identifier
        )
        let completedTaskReleased = await waitUntil(
            failureMessage: "Timed out waiting for the completed gallery task to release its slot."
        ) {
            manager.aggregateProgress?.activeDownloadCount == 1
        }
        guard completedTaskReleased else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }

        let summary = cacheStore.gallerySummaries.first {
            $0.galleryIdentifier == completedFixture.detail.identifier
        }
        XCTAssertEqual(summary?.cachedPageCount, 1)
        XCTAssertEqual(summary?.totalPageCount, 1)
        XCTAssertEqual(summary?.storageState, .persistent)
        XCTAssertFalse(cacheStore.gallerySummaries.contains { candidate in
            candidate.galleryIdentifier == completedFixture.detail.identifier
                && candidate.cachedPageCount < (candidate.totalPageCount ?? candidate.cachedPageCount)
        })

        let completedProgress = manager.progress(for: completedFixture.detail.identifier)
        XCTAssertEqual(completedProgress?.downloadedPageCount, 1)
        XCTAssertEqual(completedProgress?.totalPageCount, 1)
        XCTAssertEqual(completedProgress?.isRunning, false)
        XCTAssertNil(completedProgress?.errorMessage)
        XCTAssertEqual(manager.progress(for: blockedFixture.detail.identifier)?.isRunning, true)

        manager.startDownload(detail: completedFixture.detail)
        XCTAssertEqual(manager.progress(for: completedFixture.detail.identifier)?.isRunning, false)

        manager.pauseAllDownloads()
        client.resumeAllDataRequests()
        _ = await waitUntil(failureMessage: "Timed out cleaning up the blocked gallery request.") {
            client.activeDataRequestCount == 0
        }
    }

    /// Confirms a durable write failure is visible without downloading the image again.
    func testPersistentWriteFailureDoesNotRetryImageRequest() async throws {
        let environment = try Self.makePersistentDownloadEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = Self.downloadFixture(galleryID: 407, pageCount: 1)
        let stagedGalleryURL = environment.stagingURL.appending(
            path: fixture.detail.identifier.id,
            directoryHint: .isDirectory
        )
        let saboteur = StagingDirectorySaboteur(targetURL: stagedGalleryURL)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            beforePageCommit: { _ in
                await saboteur.replaceDirectoryWithFile()
            }
        )
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: fixture.htmlResponses,
            dataResponses: fixture.dataResponses
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxPageDownloadRetryCount: 2,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: fixture.detail)
        await waitForFinishedDownload(manager: manager, identifier: fixture.detail.identifier)

        let sabotageErrorMessage = await saboteur.errorMessage
        let sabotageInvocationCount = await saboteur.invocationCount
        XCTAssertNil(sabotageErrorMessage)
        XCTAssertEqual(sabotageInvocationCount, 1)
        let progress = try XCTUnwrap(manager.progress(for: fixture.detail.identifier))
        XCTAssertFalse(progress.isRunning)
        XCTAssertEqual(progress.downloadedPageCount, 0)
        XCTAssertEqual(progress.totalPageCount, 1)
        XCTAssertTrue(progress.errorMessage?.hasPrefix("第 1 页下载失败：") == true)
        XCTAssertEqual(client.dataRequestCount(for: fixture.imageURLs[0]), 1)
    }

    /// Confirms a cancelled run cannot remove the replacement task when it exits late.
    func testRestartedDownloadKeepsNewTaskTrackedWhenCancelledTaskFinishesLate() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let fixture = Self.downloadFixture(galleryID: 404, pageCount: 1)
        let imageURL = fixture.imageURLs[0]
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: fixture.htmlResponses,
            dataResponses: fixture.dataResponses,
            suspendedDataURLs: [imageURL]
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentPageOperations: 2,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: fixture.detail)
        let startedOriginalRequest = await waitUntil(failureMessage: "Timed out waiting for the original page request.") {
            client.requestedDataURLs.count == 1
        }
        guard startedOriginalRequest else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }

        manager.pauseAllDownloads()
        manager.startDownload(detail: fixture.detail)
        let startedReplacementRequest = await waitUntil(failureMessage: "Timed out waiting for the replacement page request.") {
            client.requestedDataURLs.count == 2
        }
        guard startedReplacementRequest else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }

        client.resumeNextDataRequest(for: imageURL)
        let cancelledRequestExited = await waitUntil(failureMessage: "Timed out waiting for the cancelled request to exit.") {
            client.completedDataRequestCount == 1
        }
        guard cancelledRequestExited else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.progress(for: fixture.detail.identifier)?.isRunning, true)
        manager.startDownload(detail: fixture.detail)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.requestedDataURLs.count, 2)

        manager.pauseAllDownloads()
        client.resumeAllDataRequests()
        _ = await waitUntil(failureMessage: "Timed out cleaning up the replacement request.") {
            client.activeDataRequestCount == 0
        }
        XCTAssertNil(cacheStore.data(for: imageURL))
    }

    /// Confirms pausing cancels permit waiters before they can start network work.
    func testPauseCancelsPagesWaitingForGlobalPermitBeforeRequestsStart() async {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheStore = ImageCacheStore(directoryURL: directoryURL)
        let fixture = Self.downloadFixture(galleryID: 405, pageCount: 2)
        let client = GalleryDownloadMockHTTPClient(
            htmlResponses: fixture.htmlResponses,
            dataResponses: fixture.dataResponses,
            suspendedDataURLs: Set(fixture.imageURLs)
        )
        let manager = GalleryDownloadManager(
            client: client,
            cacheStore: cacheStore,
            maxConcurrentPagesPerGallery: 2,
            maxConcurrentPageOperations: 1,
            retryDelayRange: 0...0
        )

        manager.startDownload(detail: fixture.detail)
        let startedPermittedRequest = await waitUntil(failureMessage: "Timed out waiting for the permitted page request.") {
            client.requestedDataURLs.count == 1
        }
        guard startedPermittedRequest else {
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }

        guard
            let requestedImageURL = client.requestedDataURLs.first,
            let requestedIndex = fixture.imageURLs.firstIndex(of: requestedImageURL)
        else {
            XCTFail("The permitted page request was not part of the fixture.")
            manager.pauseAllDownloads()
            client.resumeAllDataRequests()
            return
        }
        let waitingIndex = requestedIndex == 0 ? 1 : 0
        let waitingPageURL = fixture.pageURLs[waitingIndex]
        let waitingImageURL = fixture.imageURLs[waitingIndex]
        XCTAssertEqual(client.htmlRequestCount(for: waitingPageURL), 0)
        XCTAssertEqual(client.dataRequestCount(for: waitingImageURL), 0)

        manager.pauseAllDownloads()
        client.resumeAllDataRequests()
        _ = await waitUntil(failureMessage: "Timed out waiting for the permitted request to stop.") {
            client.activeDataRequestCount == 0
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(client.htmlRequestCount(for: waitingPageURL), 0)
        XCTAssertEqual(client.dataRequestCount(for: waitingImageURL), 0)
    }

    /// Waits for one gallery download and records a test failure on timeout.
    private func waitForFinishedDownload(
        manager: GalleryDownloadManager,
        identifier: EHGalleryIdentifier,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        _ = await waitUntil(
            timeout: timeout,
            failureMessage: "Timed out waiting for gallery \(identifier.id) to finish.",
            file: file,
            line: line
        ) {
            manager.progress(for: identifier)?.isRunning == false
        }
    }

    /// Polls a MainActor condition and records a test failure on timeout.
    private func waitUntil(
        timeout: TimeInterval = 2,
        failureMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(failureMessage, file: file, line: line)
        return false
    }

    /// Builds deterministic page and image responses for one download gallery.
    private static func downloadFixture(
        galleryID: Int,
        pageCount: Int
    ) -> (
        detail: EHGalleryDetail,
        htmlResponses: [URL: String],
        dataResponses: [URL: Result<Data, Error>],
        pageURLs: [URL],
        imageURLs: [URL]
    ) {
        let identifier = EHGalleryIdentifier(gid: galleryID, token: "abcdef1234")
        var htmlResponses: [URL: String] = [:]
        var dataResponses: [URL: Result<Data, Error>] = [:]
        var pageLinks: [EHGalleryPageLink] = []
        var pageURLs: [URL] = []
        var imageURLs: [URL] = []

        for pageNumber in 1...pageCount {
            let pageToken = String(format: "%010x", galleryID * 100 + pageNumber)
            let pageURL = URL(string: "https://e-hentai.org/s/\(pageToken)/\(galleryID)-\(pageNumber)")!
            let imageURL = URL(string: "https://example.test/\(galleryID)-\(pageNumber).webp")!
            htmlResponses[pageURL] = imagePageHTML(
                pageNumber: pageNumber,
                imageURL: imageURL,
                galleryID: galleryID
            )
            dataResponses[imageURL] = .success(Data([UInt8(truncatingIfNeeded: galleryID + pageNumber)]))
            pageLinks.append(EHGalleryPageLink(pageNumber: pageNumber, pageURL: pageURL))
            pageURLs.append(pageURL)
            imageURLs.append(imageURL)
        }

        let detail = EHGalleryDetail(
            identifier: identifier,
            title: "Gallery \(galleryID)",
            japaneseTitle: nil,
            category: "Manga",
            coverURL: nil,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: pageLinks,
            thumbnailPageURLs: [],
            pageCount: pageCount
        )
        return (detail, htmlResponses, dataResponses, pageURLs, imageURLs)
    }

    /// Creates isolated cache, staging, and finalized roots for permanent download tests.
    private static func makePersistentDownloadEnvironment() throws -> (
        baseURL: URL,
        rootURL: URL,
        stagingURL: URL,
        cacheURL: URL
    ) {
        let baseURL = FileManager.default.temporaryDirectory.appending(
            path: "GalleryDownloadManagerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return (
            baseURL,
            baseURL.appending(path: "Cached Gallery", directoryHint: .isDirectory),
            baseURL.appending(path: "Staging", directoryHint: .isDirectory),
            baseURL.appending(path: "Cache", directoryHint: .isDirectory)
        )
    }

    /// Builds minimal reader HTML that the image page parser accepts.
    private static func imagePageHTML(pageNumber: Int, imageURL: URL, galleryID: Int = 100) -> String {
        """
        <div id="i1"><h1>Sample Gallery - \(pageNumber)</h1></div>
        <div id="i2"><a id="prev" href="https://e-hentai.org/s/aaaabbbbcc/\(galleryID)-1">Prev</a><a id="next" href="https://e-hentai.org/s/eeeeffffgg/\(galleryID)-3">Next</a></div>
        <div id="i3"><img id="img" src="\(imageURL.absoluteString)" /></div>
        <div id="i5"><a href="https://e-hentai.org/g/\(galleryID)/abcdef1234/">Back</a></div>
        """
    }
}

/// Provides deterministic HTML and image responses for gallery download tests.
private final class GalleryDownloadMockHTTPClient: EHDataHTTPClient {
    private let htmlResponses: [URL: String]
    private let htmlErrors: [URL: Error]
    private let dataDelays: [URL: UInt64]
    private let suspendedDataURLs: Set<URL>
    private var dataResponses: [URL: [Result<Data, Error>]]
    private var htmlRequestCounts: [URL: Int] = [:]
    private var dataRequestCounts: [URL: Int] = [:]
    private var imageReferers: [URL: URL?] = [:]
    private var dataRequestContinuations: [URL: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var requestedDataURLs: [URL] = []
    private(set) var activeDataRequestCount = 0
    private(set) var maxConcurrentDataRequestCount = 0
    private(set) var completedDataRequestCount = 0

    /// Creates a mock client with fixed page and image responses.
    init(
        htmlResponses: [URL: String],
        dataResponses: [URL: Result<Data, Error>],
        htmlErrors: [URL: Error] = [:],
        dataDelays: [URL: UInt64] = [:],
        suspendedDataURLs: Set<URL> = []
    ) {
        self.htmlResponses = htmlResponses
        self.htmlErrors = htmlErrors
        self.dataDelays = dataDelays
        self.suspendedDataURLs = suspendedDataURLs
        self.dataResponses = dataResponses.mapValues { [$0] }
    }

    /// Creates a mock client with per-request image response sequences.
    init(
        htmlResponses: [URL: String],
        dataResponseSequences: [URL: [Result<Data, Error>]],
        htmlErrors: [URL: Error] = [:],
        dataDelays: [URL: UInt64] = [:],
        suspendedDataURLs: Set<URL> = []
    ) {
        self.htmlResponses = htmlResponses
        self.htmlErrors = htmlErrors
        self.dataDelays = dataDelays
        self.suspendedDataURLs = suspendedDataURLs
        self.dataResponses = dataResponseSequences
    }

    /// Returns configured reader page HTML.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        htmlRequestCounts[url, default: 0] += 1
        if let error = htmlErrors[url] {
            throw error
        }
        guard let body = htmlResponses[url] else {
            throw EHParseError.missingImageURL
        }
        return EHHTTPResponse(url: url, statusCode: 200, body: body)
    }

    /// Returns configured image data or throws the configured failure.
    func data(_ url: URL) async throws -> EHDataResponse {
        try await data(url, referer: nil)
    }

    /// Returns configured image data while recording the supplied referer.
    func data(_ url: URL, referer: URL?) async throws -> EHDataResponse {
        imageReferers[url] = referer
        dataRequestCounts[url, default: 0] += 1
        requestedDataURLs.append(url)
        activeDataRequestCount += 1
        maxConcurrentDataRequestCount = max(maxConcurrentDataRequestCount, activeDataRequestCount)
        defer {
            activeDataRequestCount -= 1
            completedDataRequestCount += 1
        }
        if suspendedDataURLs.contains(url) {
            await withCheckedContinuation { continuation in
                dataRequestContinuations[url, default: []].append(continuation)
            }
        }
        if let delay = dataDelays[url], delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
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

    /// Returns how many times reader HTML was requested for a URL.
    func htmlRequestCount(for url: URL) -> Int {
        htmlRequestCounts[url] ?? 0
    }

    /// Returns how many times image data was requested for a URL.
    func dataRequestCount(for url: URL) -> Int {
        dataRequestCounts[url] ?? 0
    }

    /// Returns the last referer used for an image request.
    func imageReferer(for url: URL) -> URL? {
        imageReferers[url] ?? nil
    }

    /// Resumes the oldest suspended image request for one URL.
    func resumeNextDataRequest(for url: URL) {
        guard var continuations = dataRequestContinuations[url], !continuations.isEmpty else { return }
        let continuation = continuations.removeFirst()
        dataRequestContinuations[url] = continuations
        continuation.resume()
    }

    /// Resumes every image request that is currently suspended.
    func resumeAllDataRequests() {
        let continuations = dataRequestContinuations.values.flatMap { $0 }
        dataRequestContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
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

/// Replaces a prepared staging directory with a file to force a real write failure.
private actor StagingDirectorySaboteur {
    private let targetURL: URL
    private(set) var invocationCount = 0
    private(set) var errorMessage: String?

    init(targetURL: URL) {
        self.targetURL = targetURL
    }

    /// Invalidates the staging path immediately before the page commit starts.
    func replaceDirectoryWithFile() {
        invocationCount += 1
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try Data("blocks-page-writes".utf8).write(to: targetURL, options: [.atomic])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Suspends one cache save after its file write so tests can interleave a clear.
private actor ImageCacheWriteGate {
    private var isSuspended = false
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    /// Holds the save until the test completes its clear operation.
    func suspend() async {
        isSuspended = true
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    /// Waits until the async save reaches the controlled suspension point.
    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    /// Allows the suspended save to continue after the clear has completed.
    func resume() {
        isSuspended = false
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

/// Suspends only the first cache save so a newer generation can replace its bytes.
private actor SelectiveImageCacheWriteGate {
    private var invocationCount = 0
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    /// Holds the first invocation and lets every later save continue immediately.
    func suspendFirstInvocation() async {
        invocationCount += 1
        guard invocationCount == 1 else { return }
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    /// Waits until the first save reaches the controlled suspension point.
    func waitUntilFirstInvocationSuspends() async {
        guard invocationCount > 0 else {
            await withCheckedContinuation { continuation in
                suspensionWaiters.append(continuation)
            }
            return
        }
    }

    /// Allows the stale first save to complete its generation check.
    func resumeFirstInvocation() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

/// Blocks one FIFO cache mutation so tests can enqueue ordered work behind it.
private final class ImageCacheDiskMutationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let suspendedSemaphore = DispatchSemaphore(value: 0)
    private let resumeSemaphore = DispatchSemaphore(value: 0)
    private var suspendsNextMutation = false

    /// Arms the next writer mutation without blocking the calling thread.
    func armNextMutation() {
        lock.lock()
        suspendsNextMutation = true
        lock.unlock()
    }

    /// Blocks the armed writer mutation until the test releases it.
    func suspendNextMutationIfArmed() {
        lock.lock()
        let shouldSuspend = suspendsNextMutation
        suspendsNextMutation = false
        lock.unlock()
        guard shouldSuspend else { return }
        suspendedSemaphore.signal()
        resumeSemaphore.wait()
    }

    /// Waits away from MainActor until the writer reaches the controlled mutation.
    func waitUntilSuspended() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                self.suspendedSemaphore.wait()
                continuation.resume()
            }
        }
    }

    /// Releases the blocked FIFO writer mutation.
    func resume() {
        resumeSemaphore.signal()
    }
}

/// Signals when one async cache data write has entered the FIFO queue.
private actor ImageCacheEnqueueGate {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Releases every waiter after the data write is queued.
    func signal() {
        isSignaled = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    /// Waits until the async save has queued its data transaction.
    func waitUntilSignaled() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

/// Injects one deterministic cache data-write failure by invocation number.
private final class SelectiveImageCacheDataWriteFailure: @unchecked Sendable {
    private enum ExpectedFailure: Error {
        case dataWrite
    }

    private let lock = NSLock()
    private let failingInvocation: Int
    private var invocationCount = 0

    /// Creates a failure injector for one one-based invocation.
    init(failingInvocation: Int) {
        self.failingInvocation = failingInvocation
    }

    /// Throws only for the configured FIFO data-write invocation.
    func throwIfNeeded() throws {
        lock.lock()
        invocationCount += 1
        let shouldFail = invocationCount == failingInvocation
        lock.unlock()
        if shouldFail {
            throw ExpectedFailure.dataWrite
        }
    }
}

/// Holds permanent page commits so tests can verify the complete pipeline permit boundary.
private actor DownloadPersistenceGate {
    private let expectedArrivalCount: Int
    private var arrivalCount = 0
    private var isOpen = false
    private var commitContinuations: [CheckedContinuation<Void, Never>] = []
    private var arrivalContinuations: [CheckedContinuation<Void, Never>] = []

    init(expectedArrivalCount: Int) {
        self.expectedArrivalCount = expectedArrivalCount
    }

    /// Suspends each page commit until the test opens the persistence boundary.
    func suspendUntilOpened() async {
        guard !isOpen else { return }
        arrivalCount += 1
        if arrivalCount >= expectedArrivalCount {
            let continuations = arrivalContinuations
            arrivalContinuations.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            commitContinuations.append(continuation)
        }
    }

    /// Waits until every globally permitted page reaches persistence.
    func waitUntilExpectedArrivals() async {
        guard arrivalCount < expectedArrivalCount else { return }
        await withCheckedContinuation { continuation in
            arrivalContinuations.append(continuation)
        }
    }

    /// Releases current commits and lets later commits proceed without suspension.
    func open() {
        isOpen = true
        let continuations = commitContinuations
        commitContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}
