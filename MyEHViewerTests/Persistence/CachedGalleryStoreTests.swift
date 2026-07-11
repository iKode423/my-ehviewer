import XCTest
@testable import MyEHViewer

@MainActor
final class CachedGalleryStoreTests: XCTestCase {
    /// Confirms a cached page becomes a Files-visible permanent gallery.
    func testFinalizeGalleryWritesManifestAndReadablePage() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)

        try await store.prepareGallery(summary: fixture.summary)
        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        try await store.finalizeGallery(fixture.identifier, requireComplete: false)

        let localFileURL = try XCTUnwrap(store.fileURL(for: fixture.imageURL))
        XCTAssertEqual(try Data(contentsOf: localFileURL), fixture.data)
        XCTAssertEqual(store.pageRecord(for: fixture.identifier, pageNumber: 1)?.localFileURL, localFileURL)
        let galleryFolders = try FileManager.default.contentsOfDirectory(
            at: environment.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(galleryFolders.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: galleryFolders[0].appending(path: "manifest.json").path))
        XCTAssertEqual(store.summaries.first?.storageState, .persistent)
    }

    /// Confirms durable staging counts as persistent before the gallery is finalized.
    func testStagedGallerySummaryIsPersistentAfterFirstPage() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)

        try await store.prepareGallery(summary: fixture.summary)
        XCTAssertEqual(store.summaries.first?.storageState, .cacheOnly)

        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        XCTAssertEqual(store.summaries.first?.storageState, .persistent)
    }

    /// Confirms an invalid interrupted folder is removed before a retry starts.
    func testPrepareGalleryRemovesInterruptedGarbage() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let firstStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        try await firstStore.prepareGallery(summary: fixture.summary)
        let interruptedURL = environment.stagingURL.appending(
            path: fixture.identifier.id,
            directoryHint: .isDirectory
        )
        let garbageURL = interruptedURL.appending(path: "garbage.tmp")
        try Data("garbage".utf8).write(to: garbageURL)
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )

        try await store.prepareGallery(summary: fixture.summary)

        XCTAssertFalse(FileManager.default.fileExists(atPath: garbageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: interruptedURL.appending(path: "manifest.json").path))
    }

    /// Confirms a second successful save replaces the prior gallery folder in place.
    func testSecondFinalizeReplacesExistingGalleryFolder() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        try await store.prepareGallery(summary: fixture.summary)
        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        try await store.finalizeGallery(fixture.identifier, requireComplete: false)

        let replacementData = Data("replacement-image".utf8)
        let replacementURL = environment.baseURL.appending(path: "replacement.webp")
        try replacementData.write(to: replacementURL)
        let replacementInput = CachedGalleryPageInput(
            pageNumber: fixture.input.pageNumber,
            pageURL: fixture.input.pageURL,
            imageURL: fixture.input.imageURL,
            thumbnailURL: fixture.input.thumbnailURL,
            sourceFileURL: replacementURL,
            updatedAt: Date()
        )
        try await store.prepareGallery(summary: fixture.summary)
        try await store.importCachedPage(replacementInput, identifier: fixture.identifier)
        try await store.finalizeGallery(fixture.identifier, requireComplete: false)

        let localFileURL = try XCTUnwrap(store.fileURL(for: fixture.imageURL))
        XCTAssertEqual(try Data(contentsOf: localFileURL), replacementData)
        let galleryFolders = try FileManager.default.contentsOfDirectory(
            at: environment.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(galleryFolders.count, 1)
    }

    /// Confirms permanent files take priority over duplicate disposable cache bytes.
    func testImageCacheLookupPrefersPermanentGalleryFile() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        try await persistentStore.prepareGallery(summary: fixture.summary)
        try await persistentStore.importCachedPage(fixture.input, identifier: fixture.identifier)
        try await persistentStore.finalizeGallery(fixture.identifier, requireComplete: false)
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        cacheStore.save(Data("cache-copy".utf8), for: fixture.imageURL)

        let resolvedURL = try XCTUnwrap(cacheStore.cachedDataFileURL(for: fixture.imageURL))
        XCTAssertEqual(try Data(contentsOf: resolvedURL), fixture.data)
        XCTAssertEqual(cacheStore.gallerySummaries.first?.storageState, .persistent)
    }

    /// Confirms disposable-only galleries remain distinct from durable summaries.
    func testDisposableCacheSummaryIsCacheOnly() throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let cacheStore = ImageCacheStore(directoryURL: environment.cacheURL)

        cacheStore.save(
            fixture.data,
            for: fixture.imageURL,
            responseURL: fixture.imageURL,
            context: fixture.context
        )

        XCTAssertEqual(cacheStore.gallerySummaries.first?.storageState, .cacheOnly)
    }

    /// Confirms one durable page makes a mixed gallery persistent after summary merging.
    func testMixedGallerySummaryRemainsPersistent() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        try await persistentStore.prepareGallery(summary: fixture.summary)
        try await persistentStore.importCachedPage(fixture.input, identifier: fixture.identifier)

        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let secondPageURL = URL(string: "https://e-hentai.org/s/page-token/42-2")!
        let secondImageURL = URL(string: "https://example.com/image-2.webp")!
        cacheStore.save(
            Data("cache-only-page".utf8),
            for: secondImageURL,
            responseURL: secondImageURL,
            context: ImageCacheContext(
                galleryIdentifier: fixture.identifier,
                galleryTitle: "Test Gallery",
                pageNumber: 2,
                pageURL: secondPageURL,
                totalPageCount: 2,
                thumbnailURL: fixture.imageURL
            )
        )

        let summary = try XCTUnwrap(cacheStore.gallerySummaries.first)
        XCTAssertEqual(summary.cachedPageCount, 2)
        XCTAssertEqual(summary.storageState, .persistent)
    }

    /// Confirms successful migration removes only the duplicate image-cache files.
    func testPersistAllCachedGalleriesDeletesCacheAfterFinalization() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        cacheStore.save(
            fixture.data,
            for: fixture.imageURL,
            responseURL: fixture.imageURL,
            context: fixture.context
        )

        let migratedCount = try await cacheStore.persistAllCachedGalleries()

        XCTAssertEqual(migratedCount, 1)
        XCTAssertEqual(cacheStore.snapshot.fileCount, 0)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(cacheStore.cachedDataFileURL(for: fixture.imageURL))), fixture.data)
    }

    /// Confirms a failed final replacement leaves the original cache untouched.
    func testPersistFailureDoesNotDeleteCache() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        try Data("blocks-directory".utf8).write(to: environment.rootURL)
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        cacheStore.save(
            fixture.data,
            for: fixture.imageURL,
            responseURL: fixture.imageURL,
            context: fixture.context
        )

        do {
            _ = try await cacheStore.persistAllCachedGalleries()
            XCTFail("Expected permanent gallery finalization to fail")
        } catch {
            XCTAssertTrue(cacheStore.containsData(for: fixture.imageURL))
            XCTAssertEqual(cacheStore.snapshot.fileCount, 1)
        }
    }

    /// Confirms explicit downloads bypass disposable cache files and finalize permanently.
    func testExplicitDownloadWritesDirectlyToPermanentStorage() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let persistentStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let cacheStore = ImageCacheStore(
            directoryURL: environment.cacheURL,
            persistentGalleryStore: persistentStore
        )
        let detail = EHGalleryDetail(
            identifier: fixture.identifier,
            title: "Test Gallery",
            japaneseTitle: nil,
            category: "",
            coverURL: fixture.imageURL,
            uploader: nil,
            metadata: [],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [EHGalleryPageLink(pageNumber: 1, pageURL: fixture.context.pageURL!, thumbnailURL: fixture.imageURL)],
            thumbnailPageURLs: [],
            pageCount: 1
        )

        try await cacheStore.preparePersistentDownload(detail: detail, fallback: nil)
        try await cacheStore.saveDownloadedPageAsync(
            fixture.data,
            for: fixture.imageURL,
            responseURL: fixture.imageURL,
            context: fixture.context
        )
        try await cacheStore.finalizePersistentDownload(fixture.identifier)

        XCTAssertEqual(cacheStore.snapshot.fileCount, 0)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(cacheStore.cachedDataFileURL(for: fixture.imageURL))), fixture.data)
    }

    /// Creates isolated roots for cache, staging, and Files-visible galleries.
    private func makeEnvironment() throws -> TestEnvironment {
        let baseURL = FileManager.default.temporaryDirectory.appending(
            path: "CachedGalleryStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return TestEnvironment(
            baseURL: baseURL,
            rootURL: baseURL.appending(path: "Cached Gallery", directoryHint: .isDirectory),
            stagingURL: baseURL.appending(path: "Staging", directoryHint: .isDirectory),
            cacheURL: baseURL.appending(path: "Cache", directoryHint: .isDirectory)
        )
    }

    /// Creates one single-page gallery fixture backed by a local source file.
    private func makeGalleryFixture(in baseURL: URL) throws -> GalleryFixture {
        let identifier = EHGalleryIdentifier(gid: 42, token: "token")
        let pageURL = URL(string: "https://e-hentai.org/s/page-token/42-1")!
        let imageURL = URL(string: "https://example.com/image-1.webp")!
        let data = Data("permanent-image".utf8)
        let sourceURL = baseURL.appending(path: "source.webp")
        try data.write(to: sourceURL)
        let record = CachedImagePageRecord(
            galleryIdentifier: identifier,
            galleryTitle: "Test Gallery",
            pageNumber: 1,
            pageURL: pageURL,
            imageURL: imageURL,
            cacheKey: "fixture",
            byteCount: Int64(data.count),
            totalPageCount: 1,
            thumbnailURL: imageURL,
            updatedAt: Date()
        )
        let summary = CachedGallerySummary(
            galleryIdentifier: identifier,
            title: "Test Gallery",
            thumbnailURL: imageURL,
            cachedPageCount: 1,
            totalPageCount: 1,
            byteCount: Int64(data.count),
            updatedAt: Date(),
            pageRecords: [record]
        )
        let input = CachedGalleryPageInput(
            pageNumber: 1,
            pageURL: pageURL,
            imageURL: imageURL,
            thumbnailURL: imageURL,
            sourceFileURL: sourceURL,
            updatedAt: Date()
        )
        let context = ImageCacheContext(
            galleryIdentifier: identifier,
            galleryTitle: "Test Gallery",
            pageNumber: 1,
            pageURL: pageURL,
            totalPageCount: 1,
            thumbnailURL: imageURL
        )
        return GalleryFixture(
            identifier: identifier,
            imageURL: imageURL,
            data: data,
            summary: summary,
            input: input,
            context: context
        )
    }
}

private struct TestEnvironment {
    let baseURL: URL
    let rootURL: URL
    let stagingURL: URL
    let cacheURL: URL
}

private struct GalleryFixture {
    let identifier: EHGalleryIdentifier
    let imageURL: URL
    let data: Data
    let summary: CachedGallerySummary
    let input: CachedGalleryPageInput
    let context: ImageCacheContext
}
