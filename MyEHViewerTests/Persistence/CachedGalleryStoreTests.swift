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
        XCTAssertTrue(store.hasStagedGallery(fixture.identifier))
        XCTAssertFalse(store.hasCompleteStagedGallery(fixture.identifier))
        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        XCTAssertTrue(store.hasCompleteStagedGallery(fixture.identifier))
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
        XCTAssertEqual(store.summaries.first?.isStaged, false)
        XCTAssertFalse(store.hasStagedGallery(fixture.identifier))
        XCTAssertFalse(store.hasCompleteStagedGallery(fixture.identifier))
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
        XCTAssertEqual(store.summaries.first?.isStaged, true)
        XCTAssertEqual(store.summaries.first?.isStagedComplete, false)

        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        XCTAssertEqual(store.summaries.first?.storageState, .persistent)
        XCTAssertEqual(store.summaries.first?.isStaged, true)
        XCTAssertEqual(store.summaries.first?.isStagedComplete, true)
        store.markDownloadUnavailable(
            fixture.identifier,
            title: fixture.summary.title,
            thumbnailURL: fixture.summary.thumbnailURL,
            totalPageCount: 1
        )
        XCTAssertEqual(store.summaries.first?.isDownloadUnavailable, true)
        XCTAssertEqual(store.summaries.first?.needsDownloadResume, true)
        await store.refresh()
    }

    /// Confirms out-of-order concurrent page commits merge into the latest manifest.
    func testConcurrentDownloadedPagesKeepEveryManifestEntry() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let commitGate = PageCommitGate(expectedPageCount: 3)
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            beforePageCommit: { pageNumber in
                await commitGate.wait(pageNumber: pageNumber)
            }
        )
        let summary = CachedGallerySummary(
            galleryIdentifier: fixture.identifier,
            title: fixture.summary.title,
            thumbnailURL: fixture.summary.thumbnailURL,
            cachedPageCount: 0,
            totalPageCount: 3,
            byteCount: 0,
            updatedAt: Date(),
            pageRecords: []
        )
        try await store.prepareGallery(summary: summary)

        let tasks = (1...3).map { pageNumber in
            Task {
                let pageURL = URL(string: "https://e-hentai.org/s/page-token/42-\(pageNumber)")!
                let imageURL = URL(string: "https://example.com/image-\(pageNumber).webp")!
                try await store.saveDownloadedPage(
                    Data("page-\(pageNumber)".utf8),
                    requestedURL: imageURL,
                    responseURL: imageURL,
                    context: ImageCacheContext(
                        galleryIdentifier: fixture.identifier,
                        galleryTitle: summary.title,
                        pageNumber: pageNumber,
                        pageURL: pageURL,
                        totalPageCount: 3,
                        thumbnailURL: summary.thumbnailURL
                    )
                )
            }
        }

        await commitGate.waitUntilAllPagesArrive()
        for pageNumber in [3, 2, 1] {
            await commitGate.release(pageNumber: pageNumber)
        }
        for task in tasks {
            try await task.value
        }

        XCTAssertEqual(store.summaries.first?.pageRecords.map(\.pageNumber), [1, 2, 3])
        try await store.finalizeGallery(fixture.identifier, requireComplete: true)

        let reloadedStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        XCTAssertEqual(reloadedStore.summaries.first?.pageRecords.map(\.pageNumber), [1, 2, 3])
        let galleryFolder = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: environment.rootURL,
                includingPropertiesForKeys: nil
            ).first
        )
        let storedPageNames = try FileManager.default.contentsOfDirectory(
            at: galleryFolder,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0 != "manifest.json" }
        XCTAssertEqual(storedPageNames.sorted(), ["0001.webp", "0002.webp", "0003.webp"])
    }

    /// Confirms a queued note write cannot be overwritten by a concurrent page commit.
    func testNoteMutationSurvivesConcurrentPageCommit() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let commitGate = PageCommitGate(expectedPageCount: 1)
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            beforePageCommit: { pageNumber in
                await commitGate.wait(pageNumber: pageNumber)
            }
        )
        try await store.prepareGallery(summary: fixture.summary)
        let pageTask = Task {
            try await store.saveDownloadedPage(
                fixture.data,
                requestedURL: fixture.imageURL,
                responseURL: fixture.imageURL,
                context: fixture.context
            )
        }

        await commitGate.waitUntilAllPagesArrive()
        store.setNote("Keep this note", for: fixture.identifier)
        await commitGate.release(pageNumber: 1)
        try await pageTask.value
        try await store.finalizeGallery(fixture.identifier, requireComplete: true)

        let reloadedStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        XCTAssertEqual(reloadedStore.note(for: fixture.identifier), "Keep this note")
    }

    /// Confirms a note queued after durable preparation survives before its projection appears.
    func testNoteSetBeforePreparedProjectionPersists() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let projectionGate = OneShotAsyncGate()
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            beforePreparationProjection: {
                await projectionGate.suspendOnce()
            }
        )
        let preparationTask = Task {
            try await store.prepareGallery(summary: fixture.summary)
        }

        await projectionGate.waitUntilSuspended()
        store.setNote("Queued before projection", for: fixture.identifier)
        await projectionGate.release()
        try await preparationTask.value
        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        try await store.finalizeGallery(fixture.identifier, requireComplete: true)

        let reloadedStore = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        XCTAssertEqual(reloadedStore.note(for: fixture.identifier), "Queued before projection")
    }

    /// Confirms downloaded pages update only their lookup keys until summaries are read.
    func testDownloadedPageCommitAvoidsFullGalleryProjectionRebuild() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        var fullProjectionPageCounts: [Int] = []
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            onFullProjectionRebuild: { pageCount in
                fullProjectionPageCounts.append(pageCount)
            }
        )
        let summary = CachedGallerySummary(
            galleryIdentifier: fixture.identifier,
            title: fixture.summary.title,
            thumbnailURL: fixture.summary.thumbnailURL,
            cachedPageCount: 0,
            totalPageCount: 3,
            byteCount: 0,
            updatedAt: Date(),
            pageRecords: []
        )
        try await store.prepareGallery(summary: summary)
        XCTAssertEqual(fullProjectionPageCounts, [0])

        for pageNumber in 1...3 {
            let pageURL = URL(string: "https://e-hentai.org/s/page-token/42-\(pageNumber)")!
            let imageURL = URL(string: "https://example.com/image-\(pageNumber).webp")!
            try await store.saveDownloadedPage(
                Data("page-\(pageNumber)".utf8),
                requestedURL: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: fixture.identifier,
                    galleryTitle: summary.title,
                    pageNumber: pageNumber,
                    pageURL: pageURL,
                    totalPageCount: 3,
                    thumbnailURL: summary.thumbnailURL
                )
            )
            XCTAssertEqual(store.pageRecord(for: fixture.identifier, pageNumber: pageNumber)?.imageURL, imageURL)
        }

        XCTAssertEqual(fullProjectionPageCounts, [0])
        XCTAssertEqual(store.summaries.first?.pageRecords.map(\.pageNumber), [1, 2, 3])
        XCTAssertEqual(store.summaries.first?.isStaged, true)
        XCTAssertEqual(fullProjectionPageCounts, [0])
        XCTAssertTrue(store.hasCompleteStagedGallery(fixture.identifier))
    }

    /// Confirms noncontiguous page numbers cannot satisfy durable completeness.
    func testFinalizeRejectsNoncontiguousPageNumbersWithMatchingCount() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        let summary = CachedGallerySummary(
            galleryIdentifier: fixture.identifier,
            title: fixture.summary.title,
            thumbnailURL: fixture.summary.thumbnailURL,
            cachedPageCount: 0,
            totalPageCount: 2,
            byteCount: 0,
            updatedAt: Date(),
            pageRecords: []
        )
        try await store.prepareGallery(summary: summary)
        for pageNumber in [2, 3] {
            let imageURL = URL(string: "https://example.com/noncontiguous-\(pageNumber).webp")!
            try await store.saveDownloadedPage(
                Data("page-\(pageNumber)".utf8),
                requestedURL: imageURL,
                responseURL: imageURL,
                context: ImageCacheContext(
                    galleryIdentifier: fixture.identifier,
                    galleryTitle: summary.title,
                    pageNumber: pageNumber,
                    pageURL: URL(string: "https://e-hentai.org/s/page-token/42-\(pageNumber)")!,
                    totalPageCount: 2,
                    thumbnailURL: nil
                )
            )
        }

        XCTAssertFalse(store.hasCompleteStagedGallery(fixture.identifier))
        XCTAssertEqual(store.summaries.first?.isStagedComplete, false)
        do {
            try await store.finalizeGallery(fixture.identifier, requireComplete: true)
            XCTFail("Expected noncontiguous staging to remain incomplete")
        } catch CachedGalleryStoreError.incompleteGallery {
        } catch {
            XCTFail("Unexpected finalization error: \(error)")
        }
        XCTAssertTrue(store.hasStagedGallery(fixture.identifier))
    }

    /// Confirms concurrent retries treat an already finalized gallery as success.
    func testConcurrentFinalizeRetriesAreIdempotent() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL
        )
        try await store.prepareGallery(summary: fixture.summary)
        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)

        let firstFinalization = Task {
            try await store.finalizeGallery(fixture.identifier, requireComplete: true)
        }
        let secondFinalization = Task {
            try await store.finalizeGallery(fixture.identifier, requireComplete: true)
        }
        try await firstFinalization.value
        try await secondFinalization.value

        XCTAssertFalse(store.hasStagedGallery(fixture.identifier))
        XCTAssertEqual(store.summaries.first?.isStaged, false)
        XCTAssertEqual(store.summaries.first?.cachedPageCount, 1)
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
        XCTAssertEqual(store.summaries.first?.isStaged, true)
        XCTAssertTrue(store.hasStagedGallery(fixture.identifier))

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

    /// Confirms an explicit refresh updates the actor path before a later delete command.
    func testRefreshTracksExternallyRenamedGalleryForLaterMutation() async throws {
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
        let originalFolderURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: environment.rootURL,
                includingPropertiesForKeys: nil
            ).first
        )
        let renamedFolderURL = environment.rootURL.appending(
            path: "Renamed Gallery",
            directoryHint: .isDirectory
        )
        try FileManager.default.moveItem(at: originalFolderURL, to: renamedFolderURL)

        await store.refresh()
        store.deleteGallery(fixture.identifier)
        await store.refresh()

        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedFolderURL.path))
        XCTAssertNil(store.summaries.first { $0.galleryIdentifier == fixture.identifier })
    }

    /// Confirms a rejected refresh tombstone is issued again by the next refresh.
    func testRefreshReissuesTombstoneAfterStaleProjectionWasRejected() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.baseURL) }
        let refreshGate = OneShotAsyncGate()
        let store = CachedGalleryStore(
            rootURL: environment.rootURL,
            stagingRootURL: environment.stagingURL,
            beforeRefreshProjection: {
                await refreshGate.suspendOnce()
            }
        )
        let fixture = try makeGalleryFixture(in: environment.baseURL)
        try await store.prepareGallery(summary: fixture.summary)
        try await store.importCachedPage(fixture.input, identifier: fixture.identifier)
        try await store.finalizeGallery(fixture.identifier, requireComplete: true)
        let galleryFolderURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: environment.rootURL,
                includingPropertiesForKeys: nil
            ).first
        )
        try FileManager.default.removeItem(at: galleryFolderURL)
        let staleRefreshTask = Task {
            await store.refresh()
        }

        await refreshGate.waitUntilSuspended()
        store.setNote("Reject the stale refresh", for: fixture.identifier)
        await refreshGate.release()
        await staleRefreshTask.value
        XCTAssertNotNil(store.summaries.first { $0.galleryIdentifier == fixture.identifier })

        await store.refresh()

        XCTAssertNil(store.summaries.first { $0.galleryIdentifier == fixture.identifier })
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

private actor PageCommitGate {
    private let expectedPageCount: Int
    private var continuationsByPageNumber: [Int: CheckedContinuation<Void, Never>] = [:]
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    init(expectedPageCount: Int) {
        self.expectedPageCount = expectedPageCount
    }

    /// Suspends a page until the test releases its commit in a chosen order.
    func wait(pageNumber: Int) async {
        await withCheckedContinuation { continuation in
            continuationsByPageNumber[pageNumber] = continuation
            if continuationsByPageNumber.count == expectedPageCount {
                arrivalContinuation?.resume()
                arrivalContinuation = nil
            }
        }
    }

    /// Waits until every concurrent page has reached the commit boundary.
    func waitUntilAllPagesArrive() async {
        guard continuationsByPageNumber.count < expectedPageCount else { return }
        await withCheckedContinuation { continuation in
            arrivalContinuation = continuation
        }
    }

    /// Releases one page commit without changing the remaining waiters.
    func release(pageNumber: Int) {
        continuationsByPageNumber.removeValue(forKey: pageNumber)?.resume()
    }
}

private actor OneShotAsyncGate {
    private var isSuspended = false
    private var isReleased = false
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Suspends the first caller until the test releases the boundary.
    func suspendOnce() async {
        guard !isReleased else { return }
        isSuspended = true
        suspensionContinuation?.resume()
        suspensionContinuation = nil
        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    /// Waits until production code reaches the controlled boundary.
    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionContinuation = continuation
        }
    }

    /// Releases the controlled boundary and disables later suspension.
    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
