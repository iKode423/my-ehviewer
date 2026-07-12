import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CachedGalleryPersistenceProgress: Equatable {
    let completedGalleryCount: Int
    let totalGalleryCount: Int
    let currentTitle: String

    var fraction: Double {
        guard totalGalleryCount > 0 else { return 0 }
        return Double(completedGalleryCount) / Double(totalGalleryCount)
    }
}

struct CachedGalleryPageInput: Sendable {
    let pageNumber: Int
    let pageURL: URL
    let imageURL: URL
    let thumbnailURL: URL?
    let sourceFileURL: URL
    let updatedAt: Date
}

@MainActor
final class CachedGalleryStore {
    static let shared = CachedGalleryStore(loadsInitialStateSynchronously: false)

    private var storedSummaries: [CachedGallerySummary] = []
    private var dirtySummaryGalleryIDs: Set<String> = []

    /// Returns summaries after rebuilding only galleries dirtied by page commits.
    var summaries: [CachedGallerySummary] {
        rebuildDirtyGallerySummaries()
        return storedSummaries
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let stagingRootURL: URL
    private let manifestFilename = "manifest.json"
    private var finalEntriesByGalleryID: [String: StoredGalleryEntry] = [:]
    private var stagingEntriesByGalleryID: [String: StoredGalleryEntry] = [:]
    private var activeEntriesByGalleryID: [String: StoredGalleryEntry] = [:]
    private var pageRecordByPageURL: [String: CachedImagePageRecord] = [:]
    private var pageRecordByGalleryPage: [String: CachedImagePageRecord] = [:]
    private var fileURLByImageURL: [String: URL] = [:]
    private let beforePageCommit: @Sendable (Int) async -> Void
    private let beforePreparationProjection: @Sendable () async -> Void
    private let beforeRefreshProjection: @Sendable () async -> Void
    private let onFullProjectionRebuild: (Int) -> Void
    private lazy var persistenceCoordinator = PersistenceCoordinator(
        rootURL: rootURL,
        stagingRootURL: stagingRootURL,
        manifestFilename: manifestFilename,
        finalEntriesByGalleryID: finalEntriesByGalleryID,
        stagingEntriesByGalleryID: stagingEntriesByGalleryID
    )
    private var latestProjectionRevisionByGalleryID: [String: Int] = [:]
    private var projectionGenerationByGalleryID: [String: Int] = [:]
    private var pendingPersistenceMutation: Task<Void, Never>?
    private var pendingPersistenceMutationGeneration = 0

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        stagingRootURL: URL? = nil,
        loadsInitialStateSynchronously: Bool = true,
        beforePageCommit: @escaping @Sendable (Int) async -> Void = { _ in },
        beforePreparationProjection: @escaping @Sendable () async -> Void = {},
        beforeRefreshProjection: @escaping @Sendable () async -> Void = {},
        onFullProjectionRebuild: @escaping (Int) -> Void = { _ in }
    ) {
        self.fileManager = fileManager
        self.beforePageCommit = beforePageCommit
        self.beforePreparationProjection = beforePreparationProjection
        self.beforeRefreshProjection = beforeRefreshProjection
        self.onFullProjectionRebuild = onFullProjectionRebuild
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? documentsURL.appending(path: "Cached Gallery", directoryHint: .isDirectory)
        self.stagingRootURL = stagingRootURL ?? applicationSupportURL.appending(
            path: "CachedGalleryStaging",
            directoryHint: .isDirectory
        )
        prepareDirectories()
        if loadsInitialStateSynchronously {
            loadInitialState()
        }
        _ = persistenceCoordinator
    }

    /// Reloads finalized and interrupted manifests inside the durable mutation boundary.
    func refresh() async {
        await waitForPendingPersistenceMutations()
        let expectedGenerations = projectionGenerationByGalleryID
        let mutation = await persistenceCoordinator.refreshEntriesFromDisk()
        await beforeRefreshProjection()
        applyRefreshMutation(mutation, expectedGenerations: expectedGenerations)
    }

    /// Returns the permanent or staged file for a remote image URL.
    func fileURL(for imageURL: URL) -> URL? {
        for candidateURL in HitomiImageURLMigration.equivalentURLs(for: imageURL) {
            if let fileURL = fileURLByImageURL[candidateURL.absoluteString],
               fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return nil
    }

    /// Returns a stored page by its reader page URL.
    func pageRecord(for pageURL: URL) -> CachedImagePageRecord? {
        pageRecordByPageURL[pageURL.absoluteString]
    }

    /// Returns a stored page by gallery and page number.
    func pageRecord(for identifier: EHGalleryIdentifier, pageNumber: Int) -> CachedImagePageRecord? {
        pageRecordByGalleryPage[pageKey(identifier: identifier, pageNumber: pageNumber)]
    }

    /// Returns the locally stored note for a gallery.
    func note(for identifier: EHGalleryIdentifier) -> String? {
        activeEntriesByGalleryID[identifier.id]?.manifest.note
    }

    /// Returns whether a gallery still has durable staging state.
    func hasStagedGallery(_ identifier: EHGalleryIdentifier) -> Bool {
        stagingEntriesByGalleryID[identifier.id] != nil
    }

    /// Returns whether staging contains every uniquely numbered expected page.
    func hasCompleteStagedGallery(_ identifier: EHGalleryIdentifier) -> Bool {
        guard let manifest = stagingEntriesByGalleryID[identifier.id]?.manifest else { return false }
        return Self.containsEveryExpectedPage(in: manifest)
    }

    /// Updates notes in both finalized and staged manifests.
    func setNote(_ note: String?, for identifier: EHGalleryIdentifier) {
        updateManifest(
            identifier: identifier,
            mutation: .note(note, updatedAt: Date())
        )
    }

    /// Updates gallery metadata without changing stored page files.
    func updateMetadata(detail: EHGalleryDetail, fallback: EHSearchResult?) {
        updateManifest(
            identifier: detail.identifier,
            mutation: .metadata(
                title: detail.title,
                thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL,
                totalPageCount: detail.pageCount,
                updatedAt: Date()
            )
        )
    }

    /// Marks a stored or staged gallery as unavailable for future resume attempts.
    func markDownloadUnavailable(
        _ identifier: EHGalleryIdentifier,
        title: String?,
        thumbnailURL: URL?,
        totalPageCount: Int?
    ) {
        updateManifest(
            identifier: identifier,
            mutation: .downloadUnavailable(
                title: title,
                thumbnailURL: thumbnailURL,
                totalPageCount: totalPageCount,
                updatedAt: Date()
            )
        )
    }

    /// Removes finalized and interrupted local files for one gallery.
    func deleteGallery(_ identifier: EHGalleryIdentifier) {
        let generation = advanceProjectionGeneration(for: identifier.id)
        removeGalleryFromProjection(identifier)
        enqueuePersistenceMutation { [weak self] coordinator in
            let revision = await coordinator.deleteGallery(identifier)
            await self?.applyDeletionRevision(
                revision,
                identifier: identifier,
                generation: generation
            )
        }
    }

    /// Prepares a clean staging folder while preserving verified interrupted pages.
    func prepareGallery(
        summary: CachedGallerySummary
    ) async throws {
        await waitForPendingPersistenceMutations()
        let generation = advanceProjectionGeneration(for: summary.galleryIdentifier.id)
        let mutation = try await persistenceCoordinator.prepareGallery(summary: summary)
        await beforePreparationProjection()
        applyStagingMutation(mutation, generation: generation)
    }

    /// Copies one cached page into the prepared staging gallery.
    func importCachedPage(_ input: CachedGalleryPageInput, identifier: EHGalleryIdentifier) async throws {
        try await importCachedPages([input], identifier: identifier)
    }

    /// Imports cached pages in one serialized transaction and writes one manifest.
    func importCachedPages(_ inputs: [CachedGalleryPageInput], identifier: EHGalleryIdentifier) async throws {
        guard !inputs.isEmpty else { return }
        await waitForPendingPersistenceMutations()
        let generation = currentProjectionGeneration(for: identifier.id)
        let mutation = try await persistenceCoordinator.importCachedPages(inputs, identifier: identifier)
        applyStagingMutation(mutation, generation: generation)
    }

    /// Writes one explicitly downloaded page directly into durable staging storage.
    func saveDownloadedPage(
        _ data: Data,
        requestedURL: URL,
        responseURL: URL,
        context: ImageCacheContext
    ) async throws {
        guard
            let identifier = context.galleryIdentifier,
            let pageNumber = context.pageNumber,
            let pageURL = context.pageURL
        else {
            throw CachedGalleryStoreError.invalidPageContext
        }
        await beforePageCommit(pageNumber)
        await waitForPendingPersistenceMutations()
        let generation = currentProjectionGeneration(for: identifier.id)
        let mutation = try await persistenceCoordinator.saveDownloadedPage(
            DownloadedPageCommitRequest(
                data: data,
                identifier: identifier,
                pageNumber: pageNumber,
                pageURL: pageURL,
                requestedURL: requestedURL,
                responseURL: responseURL,
                galleryTitle: context.galleryTitle,
                totalPageCount: context.totalPageCount,
                thumbnailURL: context.thumbnailURL,
                updatedAt: Date()
            )
        )
        applyDownloadedPageMutation(mutation, generation: generation)
    }

    /// Finalizes a staged gallery only after every listed file passes verification.
    func finalizeGallery(_ identifier: EHGalleryIdentifier, requireComplete: Bool) async throws {
        await waitForPendingPersistenceMutations()
        let generation = currentProjectionGeneration(for: identifier.id)
        let mutation = try await persistenceCoordinator.finalizeGallery(
            identifier,
            requireComplete: requireComplete
        )
        applyFinalizationMutation(mutation, generation: generation)
    }

    /// Removes unlisted and invalid files left by an interrupted staging operation.
    nonisolated private static func cleanStagingEntry(
        _ entry: StoredGalleryEntry,
        manifestFilename: String
    ) throws -> StoredGalleryEntry {
        let fileManager = FileManager.default
        var cleanedEntry = entry
        var validPages: [StoredGalleryPage] = []
        for page in entry.manifest.pages {
            let fileURL = entry.folderURL.appending(path: page.filename, directoryHint: .notDirectory)
            let byteCount = fileSize(at: fileURL)
            if byteCount > 0 {
                var validPage = page
                validPage.byteCount = byteCount
                validPages.append(validPage)
            } else {
                try? fileManager.removeItem(at: fileURL)
            }
        }
        cleanedEntry.manifest.pages = validPages.sorted { $0.pageNumber < $1.pageNumber }

        let expectedNames = Set(validPages.map(\.filename) + [manifestFilename])
        let contents = try fileManager.contentsOfDirectory(
            at: entry.folderURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for url in contents where !expectedNames.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
        try writeManifestStatic(cleanedEntry.manifest, to: entry.folderURL, filename: manifestFilename)
        return cleanedEntry
    }

    /// Builds a verified staging directory from existing permanent and cache files.
    nonisolated private static func prepareGalleryOnDisk(_ request: GalleryPreparationRequest) throws -> StoredGalleryEntry {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: request.stagingRootURL, withIntermediateDirectories: true)
        let stageURL = request.stagingRootURL.appending(
            path: request.summary.galleryIdentifier.id,
            directoryHint: .isDirectory
        )

        var entry: StoredGalleryEntry
        if let stagingEntry = request.stagingEntry,
           fileManager.fileExists(atPath: stagingEntry.folderURL.path) {
            entry = try cleanStagingEntry(stagingEntry, manifestFilename: request.manifestFilename)
        } else {
            try? fileManager.removeItem(at: stageURL)
            try fileManager.createDirectory(at: stageURL, withIntermediateDirectories: true)
            var manifest = StoredGalleryManifest(summary: request.summary)
            if let finalEntry = request.finalEntry {
                for page in finalEntry.manifest.pages {
                    let sourceURL = finalEntry.folderURL.appending(path: page.filename)
                    let destinationURL = stageURL.appending(path: page.filename)
                    try copyFileReplacingExisting(from: sourceURL, to: destinationURL)
                }
                manifest = finalEntry.manifest
            }
            entry = StoredGalleryEntry(manifest: manifest, folderURL: stageURL)
        }

        entry.manifest.title = request.summary.title
        entry.manifest.note = request.summary.note ?? entry.manifest.note
        entry.manifest.thumbnailURL = request.summary.thumbnailURL ?? entry.manifest.thumbnailURL
        entry.manifest.totalPageCount = request.summary.totalPageCount ?? entry.manifest.totalPageCount
        entry.manifest.isDownloadUnavailable = request.summary.isDownloadUnavailable
        entry.manifest.updatedAt = Date()
        try writeManifestStatic(entry.manifest, to: entry.folderURL, filename: request.manifestFilename)
        return entry
    }

    /// Returns whether a manifest contains every page number from one through its total.
    nonisolated private static func containsEveryExpectedPage(
        in manifest: StoredGalleryManifest
    ) -> Bool {
        guard let totalPageCount = manifest.totalPageCount, totalPageCount > 0 else { return false }
        let storedPageNumbers = Set(manifest.pages.map(\.pageNumber))
        return Set(1...totalPageCount).isSubset(of: storedPageNumbers)
    }

    /// Verifies a staged gallery and swaps it into the Files-visible directory.
    nonisolated private static func finalizeGalleryOnDisk(_ request: GalleryFinalizationRequest) throws {
        let fileManager = FileManager.default
        guard !request.entry.manifest.pages.isEmpty else {
            throw CachedGalleryStoreError.emptyGallery
        }
        for page in request.entry.manifest.pages {
            let fileURL = request.entry.folderURL.appending(path: page.filename)
            guard fileSize(at: fileURL) > 0 else {
                throw CachedGalleryStoreError.missingPageFile
            }
        }
        try writeManifestStatic(
            request.entry.manifest,
            to: request.entry.folderURL,
            filename: request.manifestFilename
        )
        try fileManager.createDirectory(at: request.rootURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: request.finalURL.path) {
            _ = try fileManager.replaceItemAt(
                request.finalURL,
                withItemAt: request.entry.folderURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: request.entry.folderURL, to: request.finalURL)
        }
        try fileManager.createDirectory(at: request.stagingRootURL, withIntermediateDirectories: true)
    }

    /// Rebuilds URL lookups and summaries with staging entries taking precedence.
    private func rebuildActiveState() {
        activeEntriesByGalleryID = finalEntriesByGalleryID
        for (galleryID, entry) in stagingEntriesByGalleryID {
            activeEntriesByGalleryID[galleryID] = entry
        }

        var pageURLLookup: [String: CachedImagePageRecord] = [:]
        var galleryPageLookup: [String: CachedImagePageRecord] = [:]
        var imageURLLookup: [String: URL] = [:]
        var rebuiltSummaries: [CachedGallerySummary] = []

        for entry in activeEntriesByGalleryID.values {
            let records = entry.manifest.pages.compactMap { page -> CachedImagePageRecord? in
                let localFileURL = entry.folderURL.appending(path: page.filename, directoryHint: .notDirectory)
                let currentByteCount = page.byteCount
                guard currentByteCount > 0 else { return nil }
                let record = CachedImagePageRecord(
                    galleryIdentifier: entry.manifest.galleryIdentifier,
                    galleryTitle: entry.manifest.title,
                    pageNumber: page.pageNumber,
                    pageURL: page.pageURL,
                    imageURL: page.imageURL,
                    cacheKey: "persistent:\(entry.manifest.galleryIdentifier.id):\(page.filename)",
                    byteCount: currentByteCount,
                    totalPageCount: entry.manifest.totalPageCount,
                    thumbnailURL: page.thumbnailURL ?? entry.manifest.thumbnailURL,
                    updatedAt: page.updatedAt,
                    localFileURL: localFileURL
                )
                pageURLLookup[page.pageURL.absoluteString] = record
                galleryPageLookup[pageKey(identifier: entry.manifest.galleryIdentifier, pageNumber: page.pageNumber)] = record
                for storedURL in [page.imageURL, page.responseImageURL].compactMap({ $0 }) {
                    for candidateURL in HitomiImageURLMigration.equivalentURLs(for: storedURL) {
                        imageURLLookup[candidateURL.absoluteString] = localFileURL
                    }
                }
                return record
            }.sorted { $0.pageNumber < $1.pageNumber }

            let isStaged = stagingEntriesByGalleryID[entry.manifest.galleryIdentifier.id] != nil
            rebuiltSummaries.append(
                CachedGallerySummary(
                    galleryIdentifier: entry.manifest.galleryIdentifier,
                    title: entry.manifest.title,
                    note: entry.manifest.note,
                    thumbnailURL: entry.manifest.thumbnailURL,
                    cachedPageCount: Set(records.map(\.pageNumber)).count,
                    totalPageCount: entry.manifest.totalPageCount,
                    byteCount: records.reduce(Int64(0)) { $0 + $1.byteCount },
                    updatedAt: entry.manifest.updatedAt,
                    pageRecords: records,
                    isDownloadUnavailable: entry.manifest.isDownloadUnavailable,
                    isStaged: isStaged,
                    isStagedComplete: isStaged && Self.containsEveryExpectedPage(in: entry.manifest),
                    storageState: records.isEmpty ? .cacheOnly : .persistent
                )
            )
        }

        pageRecordByPageURL = pageURLLookup
        pageRecordByGalleryPage = galleryPageLookup
        fileURLByImageURL = imageURLLookup
        storedSummaries = rebuiltSummaries.sorted { $0.updatedAt > $1.updatedAt }
        dirtySummaryGalleryIDs.removeAll()
    }

    /// Applies a serialized disk refresh without overwriting newer visible commands.
    private func applyRefreshMutation(
        _ mutation: StoredGalleryRefreshMutation,
        expectedGenerations: [String: Int]
    ) {
        let galleryIDs = Set(finalEntriesByGalleryID.keys)
            .union(stagingEntriesByGalleryID.keys)
            .union(mutation.revisionByGalleryID.keys)
        var didChange = false
        for galleryID in galleryIDs {
            guard expectedGenerations[galleryID, default: 0] == currentProjectionGeneration(for: galleryID),
                  let revision = mutation.revisionByGalleryID[galleryID],
                  revision > latestProjectionRevisionByGalleryID[galleryID, default: 0]
            else {
                continue
            }
            latestProjectionRevisionByGalleryID[galleryID] = revision
            finalEntriesByGalleryID[galleryID] = mutation.finalEntriesByGalleryID[galleryID]
            stagingEntriesByGalleryID[galleryID] = mutation.stagingEntriesByGalleryID[galleryID]
            didChange = true
        }
        if didChange {
            rebuildActiveState()
        }
    }

    /// Applies a preparation or import boundary by replacing one gallery projection.
    private func applyStagingMutation(_ mutation: StoredGalleryMutation, generation: Int) {
        let galleryID = mutation.entry.manifest.galleryIdentifier.id
        guard generation == currentProjectionGeneration(for: galleryID) else { return }
        guard mutation.revision > latestProjectionRevisionByGalleryID[galleryID, default: 0] else { return }
        latestProjectionRevisionByGalleryID[galleryID] = mutation.revision
        stagingEntriesByGalleryID[galleryID] = mutation.entry
        replaceActiveProjection(with: mutation.entry)
    }

    /// Applies one downloaded page without rebuilding the remaining page projection.
    private func applyDownloadedPageMutation(_ mutation: StoredGalleryPageMutation, generation: Int) {
        let galleryID = mutation.entry.manifest.galleryIdentifier.id
        guard generation == currentProjectionGeneration(for: galleryID) else { return }
        guard mutation.revision > latestProjectionRevisionByGalleryID[galleryID, default: 0] else { return }

        if let replacedPage = mutation.replacedPage,
           let previousEntry = activeEntriesByGalleryID[galleryID] {
            removeProjection(for: replacedPage, in: previousEntry)
        }
        latestProjectionRevisionByGalleryID[galleryID] = mutation.revision
        stagingEntriesByGalleryID[galleryID] = mutation.entry
        activeEntriesByGalleryID[galleryID] = mutation.entry
        _ = installProjection(for: mutation.page, in: mutation.entry)
        dirtySummaryGalleryIDs.insert(galleryID)
    }

    /// Applies a completed folder move without rescanning either storage root.
    private func applyFinalizationMutation(_ mutation: StoredGalleryFinalizationMutation, generation: Int) {
        let galleryID = mutation.entry.manifest.galleryIdentifier.id
        guard generation == currentProjectionGeneration(for: galleryID) else { return }
        guard mutation.revision > latestProjectionRevisionByGalleryID[galleryID, default: 0] else { return }
        latestProjectionRevisionByGalleryID[galleryID] = mutation.revision
        stagingEntriesByGalleryID.removeValue(forKey: galleryID)
        finalEntriesByGalleryID[galleryID] = mutation.entry
        replaceActiveProjection(with: mutation.entry)
    }

    /// Reconciles a completed metadata write with any page result that raced it.
    private func applyManifestPersistenceMutation(
        _ mutation: StoredGalleryManifestPersistenceMutation,
        generation: Int
    ) {
        let galleryID = mutation.identifier.id
        guard generation == currentProjectionGeneration(for: galleryID) else { return }
        guard mutation.revision > latestProjectionRevisionByGalleryID[galleryID, default: 0] else { return }
        latestProjectionRevisionByGalleryID[galleryID] = mutation.revision
        if let finalEntry = mutation.finalEntry {
            finalEntriesByGalleryID[galleryID] = finalEntry
        } else {
            finalEntriesByGalleryID.removeValue(forKey: galleryID)
        }
        if let stagingEntry = mutation.stagingEntry {
            stagingEntriesByGalleryID[galleryID] = stagingEntry
        } else {
            stagingEntriesByGalleryID.removeValue(forKey: galleryID)
        }
        if let activeEntry = mutation.stagingEntry ?? mutation.finalEntry {
            replaceActiveProjection(with: activeEntry)
        }
    }

    /// Prevents an older in-flight page result from restoring a deleted gallery.
    private func applyDeletionRevision(
        _ revision: Int,
        identifier: EHGalleryIdentifier,
        generation: Int
    ) {
        guard generation == currentProjectionGeneration(for: identifier.id) else { return }
        guard revision > latestProjectionRevisionByGalleryID[identifier.id, default: 0] else { return }
        removeGalleryFromProjection(identifier)
        latestProjectionRevisionByGalleryID[identifier.id] = revision
    }

    /// Removes one gallery from every synchronous lookup without touching disk.
    private func removeGalleryFromProjection(_ identifier: EHGalleryIdentifier) {
        if let activeEntry = activeEntriesByGalleryID[identifier.id] {
            removeProjection(for: activeEntry)
        }
        finalEntriesByGalleryID.removeValue(forKey: identifier.id)
        stagingEntriesByGalleryID.removeValue(forKey: identifier.id)
        activeEntriesByGalleryID.removeValue(forKey: identifier.id)
        dirtySummaryGalleryIDs.remove(identifier.id)
        storedSummaries.removeAll { $0.galleryIdentifier == identifier }
    }

    /// Rebuilds lookup records for one gallery from manifest byte counts only.
    private func replaceActiveProjection(with entry: StoredGalleryEntry) {
        let galleryID = entry.manifest.galleryIdentifier.id
        onFullProjectionRebuild(entry.manifest.pages.count)
        if let previousEntry = activeEntriesByGalleryID[galleryID] {
            removeProjection(for: previousEntry)
        }
        activeEntriesByGalleryID[galleryID] = entry

        let records = entry.manifest.pages
            .compactMap { installProjection(for: $0, in: entry) }
            .sorted { $0.pageNumber < $1.pageNumber }
        replaceStoredSummary(for: entry, records: records)
    }

    /// Removes lookup keys owned by one previous gallery projection.
    private func removeProjection(for entry: StoredGalleryEntry) {
        for page in entry.manifest.pages {
            removeProjection(for: page, in: entry)
        }
    }

    /// Installs lookup keys for one stored page and returns its summary record.
    @discardableResult
    private func installProjection(
        for page: StoredGalleryPage,
        in entry: StoredGalleryEntry
    ) -> CachedImagePageRecord? {
        guard let record = makePageRecord(for: page, in: entry) else { return nil }
        let localFileURL = entry.folderURL.appending(path: page.filename, directoryHint: .notDirectory)
        pageRecordByPageURL[page.pageURL.absoluteString] = record
        pageRecordByGalleryPage[pageKey(
            identifier: entry.manifest.galleryIdentifier,
            pageNumber: page.pageNumber
        )] = record
        for storedURL in [page.imageURL, page.responseImageURL].compactMap({ $0 }) {
            for candidateURL in HitomiImageURLMigration.equivalentURLs(for: storedURL) {
                fileURLByImageURL[candidateURL.absoluteString] = localFileURL
            }
        }
        return record
    }

    /// Removes lookup keys owned by one stored page only.
    private func removeProjection(for page: StoredGalleryPage, in entry: StoredGalleryEntry) {
        let localFileURL = entry.folderURL.appending(path: page.filename, directoryHint: .notDirectory)
        let pageURLKey = page.pageURL.absoluteString
        if pageRecordByPageURL[pageURLKey]?.localFileURL == localFileURL {
            pageRecordByPageURL.removeValue(forKey: pageURLKey)
        }
        pageRecordByGalleryPage.removeValue(forKey: pageKey(
            identifier: entry.manifest.galleryIdentifier,
            pageNumber: page.pageNumber
        ))
        for storedURL in [page.imageURL, page.responseImageURL].compactMap({ $0 }) {
            for candidateURL in HitomiImageURLMigration.equivalentURLs(for: storedURL) {
                let key = candidateURL.absoluteString
                if fileURLByImageURL[key] == localFileURL {
                    fileURLByImageURL.removeValue(forKey: key)
                }
            }
        }
    }

    /// Creates one lightweight page record from durable manifest values.
    private func makePageRecord(
        for page: StoredGalleryPage,
        in entry: StoredGalleryEntry
    ) -> CachedImagePageRecord? {
        guard page.byteCount > 0 else { return nil }
        let localFileURL = entry.folderURL.appending(path: page.filename, directoryHint: .notDirectory)
        return CachedImagePageRecord(
            galleryIdentifier: entry.manifest.galleryIdentifier,
            galleryTitle: entry.manifest.title,
            pageNumber: page.pageNumber,
            pageURL: page.pageURL,
            imageURL: page.imageURL,
            cacheKey: "persistent:\(entry.manifest.galleryIdentifier.id):\(page.filename)",
            byteCount: page.byteCount,
            totalPageCount: entry.manifest.totalPageCount,
            thumbnailURL: page.thumbnailURL ?? entry.manifest.thumbnailURL,
            updatedAt: page.updatedAt,
            localFileURL: localFileURL
        )
    }

    /// Rebuilds dirty summaries once when a publication boundary reads them.
    private func rebuildDirtyGallerySummaries() {
        guard !dirtySummaryGalleryIDs.isEmpty else { return }
        let galleryIDs = dirtySummaryGalleryIDs
        dirtySummaryGalleryIDs.removeAll()
        for galleryID in galleryIDs {
            storedSummaries.removeAll { $0.galleryIdentifier.id == galleryID }
            guard let entry = activeEntriesByGalleryID[galleryID] else { continue }
            let records = entry.manifest.pages
                .compactMap { makePageRecord(for: $0, in: entry) }
                .sorted { $0.pageNumber < $1.pageNumber }
            storedSummaries.append(makeSummary(for: entry, records: records))
        }
        storedSummaries.sort { $0.updatedAt > $1.updatedAt }
    }

    /// Replaces one stored summary at a preparation, import, or finalization boundary.
    private func replaceStoredSummary(
        for entry: StoredGalleryEntry,
        records: [CachedImagePageRecord]
    ) {
        let galleryID = entry.manifest.galleryIdentifier.id
        dirtySummaryGalleryIDs.remove(galleryID)
        storedSummaries.removeAll { $0.galleryIdentifier.id == galleryID }
        storedSummaries.append(makeSummary(for: entry, records: records))
        storedSummaries.sort { $0.updatedAt > $1.updatedAt }
    }

    /// Creates one gallery summary from an already built page record list.
    private func makeSummary(
        for entry: StoredGalleryEntry,
        records: [CachedImagePageRecord]
    ) -> CachedGallerySummary {
        let isStaged = stagingEntriesByGalleryID[entry.manifest.galleryIdentifier.id] != nil
        return CachedGallerySummary(
            galleryIdentifier: entry.manifest.galleryIdentifier,
            title: entry.manifest.title,
            note: entry.manifest.note,
            thumbnailURL: entry.manifest.thumbnailURL,
            cachedPageCount: Set(records.map(\.pageNumber)).count,
            totalPageCount: entry.manifest.totalPageCount,
            byteCount: records.reduce(Int64(0)) { $0 + $1.byteCount },
            updatedAt: entry.manifest.updatedAt,
            pageRecords: records,
            isDownloadUnavailable: entry.manifest.isDownloadUnavailable,
            isStaged: isStaged,
            isStagedComplete: isStaged && Self.containsEveryExpectedPage(in: entry.manifest),
            storageState: records.isEmpty ? .cacheOnly : .persistent
        )
    }

    /// Advances one gallery's projection fence before issuing a newer visible command.
    private func advanceProjectionGeneration(for galleryID: String) -> Int {
        let generation = projectionGenerationByGalleryID[galleryID, default: 0] + 1
        projectionGenerationByGalleryID[galleryID] = generation
        return generation
    }

    /// Returns the issue-time fence used to reject older asynchronous projection results.
    private func currentProjectionGeneration(for galleryID: String) -> Int {
        projectionGenerationByGalleryID[galleryID, default: 0]
    }

    /// Orders synchronous metadata commands before later async disk transactions.
    private func enqueuePersistenceMutation(
        _ operation: @escaping @Sendable (PersistenceCoordinator) async -> Void
    ) {
        let previousTask = pendingPersistenceMutation
        let coordinator = persistenceCoordinator
        pendingPersistenceMutationGeneration += 1
        let generation = pendingPersistenceMutationGeneration
        pendingPersistenceMutation = Task {
            await previousTask?.value
            await operation(coordinator)
            if pendingPersistenceMutationGeneration == generation {
                pendingPersistenceMutation = nil
            }
        }
    }

    /// Waits until every metadata or deletion command already queued has reached disk.
    private func waitForPendingPersistenceMutations() async {
        while let task = pendingPersistenceMutation {
            let generation = pendingPersistenceMutationGeneration
            await task.value
            guard generation != pendingPersistenceMutationGeneration else { return }
        }
    }

    /// Queues a manifest change even when preparation has not reached the UI projection yet.
    private func updateManifest(
        identifier: EHGalleryIdentifier,
        mutation: StoredGalleryManifestMutation
    ) {
        var changed = false
        if var finalEntry = finalEntriesByGalleryID[identifier.id] {
            mutation.apply(to: &finalEntry.manifest)
            finalEntriesByGalleryID[identifier.id] = finalEntry
            changed = true
        }
        if var stagingEntry = stagingEntriesByGalleryID[identifier.id] {
            mutation.apply(to: &stagingEntry.manifest)
            stagingEntriesByGalleryID[identifier.id] = stagingEntry
            changed = true
        }
        let generation = advanceProjectionGeneration(for: identifier.id)
        if changed {
            if let activeEntry = stagingEntriesByGalleryID[identifier.id]
                ?? finalEntriesByGalleryID[identifier.id] {
                replaceActiveProjection(with: activeEntry)
            }
        }
        enqueuePersistenceMutation { coordinator in
            guard let persistedMutation = await coordinator.updateManifest(
                identifier: identifier,
                mutation: mutation
            ) else {
                return
            }
            await self.applyManifestPersistenceMutation(
                persistedMutation,
                generation: generation
            )
        }
    }

    /// Loads startup manifests before the persistence actor begins accepting mutations.
    private func loadInitialState() {
        finalEntriesByGalleryID = loadEntries(in: rootURL)
        stagingEntriesByGalleryID = loadEntries(in: stagingRootURL)
        rebuildActiveState()
    }

    /// Loads valid manifests from one gallery storage root.
    private func loadEntries(in directoryURL: URL) -> [String: StoredGalleryEntry] {
        Self.loadEntriesFromDisk(
            in: directoryURL,
            manifestFilename: manifestFilename,
            fileManager: fileManager
        )
    }

    /// Scans one storage root and normalizes page byte counts outside MainActor when requested by the actor.
    nonisolated private static func loadEntriesFromDisk(
        in directoryURL: URL,
        manifestFilename: String,
        fileManager: FileManager
    ) -> [String: StoredGalleryEntry] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        var entries: [String: StoredGalleryEntry] = [:]
        for folderURL in urls {
            guard
                let values = try? folderURL.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true,
                let data = try? Data(contentsOf: folderURL.appending(path: manifestFilename)),
                var manifest = try? Self.decodeManifest(data)
            else {
                continue
            }
            manifest.pages = manifest.pages.compactMap { page in
                let byteCount = fileSize(at: folderURL.appending(path: page.filename))
                guard byteCount > 0 else { return nil }
                var normalizedPage = page
                normalizedPage.byteCount = byteCount
                return normalizedPage
            }
            entries[manifest.galleryIdentifier.id] = StoredGalleryEntry(manifest: manifest, folderURL: folderURL)
        }
        return entries
    }

    /// Creates Files-visible and private staging roots.
    private func prepareDirectories() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
    }

    /// Writes a manifest without requiring main-actor state.
    nonisolated private static func writeManifestStatic(
        _ manifest: StoredGalleryManifest,
        to folderURL: URL,
        filename: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: folderURL.appending(path: filename, directoryHint: .notDirectory),
            options: [.atomic]
        )
    }

    /// Decodes ISO-8601 dates used by durable manifests.
    nonisolated private static func decodeManifest(_ data: Data) throws -> StoredGalleryManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredGalleryManifest.self, from: data)
    }

    /// Copies a file after removing an older destination.
    nonisolated private static func copyFileReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else { return }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    /// Produces a stable Files folder name for one gallery.
    nonisolated private static func folderName(for manifest: StoredGalleryManifest) -> String {
        let siteName = manifest.galleryIdentifier.site == .hitomi ? "Hitomi" : "E-Hentai"
        let title = sanitizedPathComponent(manifest.title)
        return "[\(siteName)-\(manifest.galleryIdentifier.id)] \(title)"
    }

    /// Removes path separators and limits title length for Files compatibility.
    nonisolated private static func sanitizedPathComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = value.components(separatedBy: invalidCharacters)
        let joined = pieces.joined(separator: " ")
        let normalized = joined.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let fallback = normalized.isEmpty ? "Gallery" : normalized
        return String(fallback.prefix(80))
    }

    /// Produces a numbered filename while preserving the actual image format.
    nonisolated private static func pageFilename(pageNumber: Int, sourceFileURL: URL, imageURL: URL) -> String {
        let fileExtension = preferredFileExtension(sourceFileURL: sourceFileURL, imageURLs: [imageURL])
        return String(format: "%04d.%@", pageNumber, fileExtension)
    }

    /// Produces a numbered filename for freshly downloaded image data.
    nonisolated private static func pageFilename(pageNumber: Int, data: Data, imageURLs: [URL]) -> String {
        let fileExtension = preferredFileExtension(data: data, imageURLs: imageURLs)
        return String(format: "%04d.%@", pageNumber, fileExtension)
    }

    /// Resolves an extension from ImageIO before using the remote path extension.
    nonisolated private static func preferredFileExtension(sourceFileURL: URL, imageURLs: [URL]) -> String {
        if let source = CGImageSourceCreateWithURL(sourceFileURL as CFURL, nil),
           let type = CGImageSourceGetType(source),
           let extensionName = UTType(type as String)?.preferredFilenameExtension {
            return extensionName.lowercased()
        }
        return remoteFileExtension(imageURLs) ?? "img"
    }

    /// Resolves an extension from downloaded bytes before using the remote path extension.
    nonisolated private static func preferredFileExtension(data: Data, imageURLs: [URL]) -> String {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source),
           let extensionName = UTType(type as String)?.preferredFilenameExtension {
            return extensionName.lowercased()
        }
        return remoteFileExtension(imageURLs) ?? "img"
    }

    /// Returns a conservative remote filename extension.
    nonisolated private static func remoteFileExtension(_ imageURLs: [URL]) -> String? {
        imageURLs.lazy
            .map { $0.pathExtension.lowercased() }
            .first { !$0.isEmpty && $0.count <= 8 && $0.allSatisfy { $0.isLetter || $0.isNumber } }
    }

    /// Reads one file size without loading its contents.
    nonisolated private static func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// Builds the stable dictionary key for one gallery page.
    private func pageKey(identifier: EHGalleryIdentifier, pageNumber: Int) -> String {
        "\(identifier.id):\(pageNumber)"
    }

    /// Builds the stable dictionary key without actor-isolated state.
    private static func pageKey(identifier: EHGalleryIdentifier, pageNumber: Int) -> String {
        "\(identifier.id):\(pageNumber)"
    }

    /// Serializes every durable gallery mutation and owns the latest manifests.
    private actor PersistenceCoordinator {
        private let fileManager = FileManager.default
        private let rootURL: URL
        private let stagingRootURL: URL
        private let manifestFilename: String
        private var finalEntriesByGalleryID: [String: StoredGalleryEntry]
        private var stagingEntriesByGalleryID: [String: StoredGalleryEntry]
        private var revisionByGalleryID: [String: Int] = [:]

        init(
            rootURL: URL,
            stagingRootURL: URL,
            manifestFilename: String,
            finalEntriesByGalleryID: [String: StoredGalleryEntry],
            stagingEntriesByGalleryID: [String: StoredGalleryEntry]
        ) {
            self.rootURL = rootURL
            self.stagingRootURL = stagingRootURL
            self.manifestFilename = manifestFilename
            self.finalEntriesByGalleryID = finalEntriesByGalleryID
            self.stagingEntriesByGalleryID = stagingEntriesByGalleryID
        }

        /// Reloads both roots after earlier actor mutations and advances per-gallery revisions.
        func refreshEntriesFromDisk() -> StoredGalleryRefreshMutation {
            let refreshedFinalEntries = CachedGalleryStore.loadEntriesFromDisk(
                in: rootURL,
                manifestFilename: manifestFilename,
                fileManager: fileManager
            )
            let refreshedStagingEntries = CachedGalleryStore.loadEntriesFromDisk(
                in: stagingRootURL,
                manifestFilename: manifestFilename,
                fileManager: fileManager
            )
            let galleryIDs = Set(finalEntriesByGalleryID.keys)
                .union(stagingEntriesByGalleryID.keys)
                .union(refreshedFinalEntries.keys)
                .union(refreshedStagingEntries.keys)
                .union(revisionByGalleryID.keys)
            finalEntriesByGalleryID = refreshedFinalEntries
            stagingEntriesByGalleryID = refreshedStagingEntries
            let revisions = Dictionary(uniqueKeysWithValues: galleryIDs.map { galleryID in
                (galleryID, nextRevision(for: galleryID))
            })
            return StoredGalleryRefreshMutation(
                finalEntriesByGalleryID: refreshedFinalEntries,
                stagingEntriesByGalleryID: refreshedStagingEntries,
                revisionByGalleryID: revisions
            )
        }

        /// Refreshes Files-visible state, then cleans or creates verified staging storage.
        func prepareGallery(summary: CachedGallerySummary) throws -> StoredGalleryMutation {
            try Task.checkCancellation()
            finalEntriesByGalleryID = CachedGalleryStore.loadEntriesFromDisk(
                in: rootURL,
                manifestFilename: manifestFilename,
                fileManager: fileManager
            )
            stagingEntriesByGalleryID = CachedGalleryStore.loadEntriesFromDisk(
                in: stagingRootURL,
                manifestFilename: manifestFilename,
                fileManager: fileManager
            )
            let galleryID = summary.galleryIdentifier.id
            let request = GalleryPreparationRequest(
                summary: summary,
                finalEntry: finalEntriesByGalleryID[galleryID],
                stagingEntry: stagingEntriesByGalleryID[galleryID],
                stagingRootURL: stagingRootURL,
                manifestFilename: manifestFilename
            )
            let entry = try CachedGalleryStore.prepareGalleryOnDisk(request)
            stagingEntriesByGalleryID[galleryID] = entry
            return StoredGalleryMutation(entry: entry, revision: nextRevision(for: galleryID))
        }

        /// Copies cached pages and commits their merged manifest once.
        func importCachedPages(
            _ inputs: [CachedGalleryPageInput],
            identifier: EHGalleryIdentifier
        ) throws -> StoredGalleryMutation {
            try Task.checkCancellation()
            let galleryID = identifier.id
            guard var entry = stagingEntriesByGalleryID[galleryID] else {
                throw CachedGalleryStoreError.stagingNotPrepared
            }

            for input in inputs {
                let oldPage = entry.manifest.pages.first { $0.pageNumber == input.pageNumber }
                let filename = CachedGalleryStore.pageFilename(
                    pageNumber: input.pageNumber,
                    sourceFileURL: input.sourceFileURL,
                    imageURL: input.imageURL
                )
                let destinationURL = entry.folderURL.appending(path: filename, directoryHint: .notDirectory)
                try CachedGalleryStore.copyFileReplacingExisting(
                    from: input.sourceFileURL,
                    to: destinationURL
                )
                if let oldPage, oldPage.filename != filename {
                    try? fileManager.removeItem(at: entry.folderURL.appending(path: oldPage.filename))
                }
                entry.manifest.pages.removeAll { $0.pageNumber == input.pageNumber }
                entry.manifest.pages.append(
                    StoredGalleryPage(
                        pageNumber: input.pageNumber,
                        pageURL: input.pageURL,
                        imageURL: input.imageURL,
                        responseImageURL: nil,
                        thumbnailURL: input.thumbnailURL,
                        filename: filename,
                        byteCount: CachedGalleryStore.fileSize(at: destinationURL),
                        updatedAt: input.updatedAt
                    )
                )
            }

            entry.manifest.pages.sort { $0.pageNumber < $1.pageNumber }
            entry.manifest.updatedAt = Date()
            try CachedGalleryStore.writeManifestStatic(
                entry.manifest,
                to: entry.folderURL,
                filename: manifestFilename
            )
            stagingEntriesByGalleryID[galleryID] = entry
            return StoredGalleryMutation(entry: entry, revision: nextRevision(for: galleryID))
        }

        /// Commits one downloaded page against the actor's latest manifest without suspension.
        func saveDownloadedPage(_ request: DownloadedPageCommitRequest) throws -> StoredGalleryPageMutation {
            try Task.checkCancellation()
            let galleryID = request.identifier.id
            guard var entry = stagingEntriesByGalleryID[galleryID] else {
                throw CachedGalleryStoreError.stagingNotPrepared
            }
            let filename = CachedGalleryStore.pageFilename(
                pageNumber: request.pageNumber,
                data: request.data,
                imageURLs: [request.responseURL, request.requestedURL]
            )
            let destinationURL = entry.folderURL.appending(path: filename, directoryHint: .notDirectory)
            let oldPage = entry.manifest.pages.first { $0.pageNumber == request.pageNumber }
            try request.data.write(to: destinationURL, options: [.atomic])
            if let oldPage, oldPage.filename != filename {
                try? fileManager.removeItem(at: entry.folderURL.appending(path: oldPage.filename))
            }

            entry.manifest.title = request.galleryTitle ?? entry.manifest.title
            entry.manifest.thumbnailURL = request.thumbnailURL ?? entry.manifest.thumbnailURL
            entry.manifest.totalPageCount = request.totalPageCount ?? entry.manifest.totalPageCount
            entry.manifest.updatedAt = request.updatedAt
            entry.manifest.pages.removeAll { $0.pageNumber == request.pageNumber }
            let page = StoredGalleryPage(
                pageNumber: request.pageNumber,
                pageURL: request.pageURL,
                imageURL: request.requestedURL,
                responseImageURL: request.responseURL == request.requestedURL ? nil : request.responseURL,
                thumbnailURL: request.thumbnailURL,
                filename: filename,
                byteCount: Int64(request.data.count),
                updatedAt: request.updatedAt
            )
            entry.manifest.pages.append(page)
            entry.manifest.pages.sort { $0.pageNumber < $1.pageNumber }
            try CachedGalleryStore.writeManifestStatic(
                entry.manifest,
                to: entry.folderURL,
                filename: manifestFilename
            )
            stagingEntriesByGalleryID[galleryID] = entry
            return StoredGalleryPageMutation(
                entry: entry,
                page: page,
                replacedPage: oldPage,
                revision: nextRevision(for: galleryID)
            )
        }

        /// Verifies and moves one staged gallery before returning the final folder entry.
        func finalizeGallery(
            _ identifier: EHGalleryIdentifier,
            requireComplete: Bool
        ) throws -> StoredGalleryFinalizationMutation {
            try Task.checkCancellation()
            let galleryID = identifier.id
            guard var entry = stagingEntriesByGalleryID[galleryID] else {
                guard let finalEntry = finalEntriesByGalleryID[galleryID] else {
                    throw CachedGalleryStoreError.stagingNotPrepared
                }
                if requireComplete,
                   !CachedGalleryStore.containsEveryExpectedPage(in: finalEntry.manifest) {
                    throw CachedGalleryStoreError.incompleteGallery
                }
                for page in finalEntry.manifest.pages {
                    let fileURL = finalEntry.folderURL.appending(path: page.filename)
                    guard CachedGalleryStore.fileSize(at: fileURL) > 0 else {
                        throw CachedGalleryStoreError.missingPageFile
                    }
                }
                return StoredGalleryFinalizationMutation(
                    entry: finalEntry,
                    revision: nextRevision(for: galleryID)
                )
            }
            let containsEveryExpectedPage = CachedGalleryStore.containsEveryExpectedPage(
                in: entry.manifest
            )
            if requireComplete, !containsEveryExpectedPage {
                throw CachedGalleryStoreError.incompleteGallery
            }
            entry.manifest.isComplete = containsEveryExpectedPage
            entry.manifest.updatedAt = Date()
            let finalURL = finalEntriesByGalleryID[galleryID]?.folderURL
                ?? rootURL.appending(
                    path: CachedGalleryStore.folderName(for: entry.manifest),
                    directoryHint: .isDirectory
                )
            try CachedGalleryStore.finalizeGalleryOnDisk(
                GalleryFinalizationRequest(
                    entry: entry,
                    finalURL: finalURL,
                    rootURL: rootURL,
                    stagingRootURL: stagingRootURL,
                    manifestFilename: manifestFilename
                )
            )

            let finalEntry = StoredGalleryEntry(manifest: entry.manifest, folderURL: finalURL)
            stagingEntriesByGalleryID.removeValue(forKey: galleryID)
            finalEntriesByGalleryID[galleryID] = finalEntry
            return StoredGalleryFinalizationMutation(
                entry: finalEntry,
                revision: nextRevision(for: galleryID)
            )
        }

        /// Persists metadata through the same ordering boundary as page commits.
        func updateManifest(
            identifier: EHGalleryIdentifier,
            mutation: StoredGalleryManifestMutation
        ) -> StoredGalleryManifestPersistenceMutation? {
            var changed = false
            if var finalEntry = finalEntriesByGalleryID[identifier.id] {
                mutation.apply(to: &finalEntry.manifest)
                if (try? CachedGalleryStore.writeManifestStatic(
                    finalEntry.manifest,
                    to: finalEntry.folderURL,
                    filename: manifestFilename
                )) != nil {
                    finalEntriesByGalleryID[identifier.id] = finalEntry
                    changed = true
                }
            }
            if var stagingEntry = stagingEntriesByGalleryID[identifier.id] {
                mutation.apply(to: &stagingEntry.manifest)
                if (try? CachedGalleryStore.writeManifestStatic(
                    stagingEntry.manifest,
                    to: stagingEntry.folderURL,
                    filename: manifestFilename
                )) != nil {
                    stagingEntriesByGalleryID[identifier.id] = stagingEntry
                    changed = true
                }
            }
            guard changed else { return nil }
            return StoredGalleryManifestPersistenceMutation(
                identifier: identifier,
                finalEntry: finalEntriesByGalleryID[identifier.id],
                stagingEntry: stagingEntriesByGalleryID[identifier.id],
                revision: nextRevision(for: identifier.id)
            )
        }

        /// Removes durable folders after earlier queued transactions finish.
        func deleteGallery(_ identifier: EHGalleryIdentifier) -> Int {
            let urls = [
                finalEntriesByGalleryID[identifier.id]?.folderURL,
                stagingEntriesByGalleryID[identifier.id]?.folderURL
            ].compactMap { $0 }
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
            finalEntriesByGalleryID.removeValue(forKey: identifier.id)
            stagingEntriesByGalleryID.removeValue(forKey: identifier.id)
            return nextRevision(for: identifier.id)
        }

        /// Advances one gallery revision so delayed MainActor results cannot win.
        private func nextRevision(for galleryID: String) -> Int {
            let revision = revisionByGalleryID[galleryID, default: 0] + 1
            revisionByGalleryID[galleryID] = revision
            return revision
        }
    }
}

private struct StoredGalleryEntry: Sendable {
    var manifest: StoredGalleryManifest
    let folderURL: URL
}

private struct StoredGalleryManifest: Codable, Sendable {
    var version = 1
    let galleryIdentifier: EHGalleryIdentifier
    var title: String
    var note: String?
    var thumbnailURL: URL?
    var totalPageCount: Int?
    var updatedAt: Date
    var isComplete: Bool
    var isDownloadUnavailable: Bool
    var pages: [StoredGalleryPage]

    /// Creates a durable manifest from an existing cache summary.
    init(summary: CachedGallerySummary) {
        galleryIdentifier = summary.galleryIdentifier
        title = summary.title
        note = summary.note
        thumbnailURL = summary.thumbnailURL
        totalPageCount = summary.totalPageCount
        updatedAt = Date()
        isComplete = false
        isDownloadUnavailable = summary.isDownloadUnavailable
        pages = []
    }
}

private struct StoredGalleryPage: Codable, Sendable {
    let pageNumber: Int
    let pageURL: URL
    let imageURL: URL
    let responseImageURL: URL?
    let thumbnailURL: URL?
    let filename: String
    var byteCount: Int64
    let updatedAt: Date
}

private struct DownloadedPageCommitRequest: Sendable {
    let data: Data
    let identifier: EHGalleryIdentifier
    let pageNumber: Int
    let pageURL: URL
    let requestedURL: URL
    let responseURL: URL
    let galleryTitle: String?
    let totalPageCount: Int?
    let thumbnailURL: URL?
    let updatedAt: Date
}

private struct StoredGalleryMutation: Sendable {
    let entry: StoredGalleryEntry
    let revision: Int
}

private struct StoredGalleryPageMutation: Sendable {
    let entry: StoredGalleryEntry
    let page: StoredGalleryPage
    let replacedPage: StoredGalleryPage?
    let revision: Int
}

private struct StoredGalleryRefreshMutation: Sendable {
    let finalEntriesByGalleryID: [String: StoredGalleryEntry]
    let stagingEntriesByGalleryID: [String: StoredGalleryEntry]
    let revisionByGalleryID: [String: Int]
}

private struct StoredGalleryFinalizationMutation: Sendable {
    let entry: StoredGalleryEntry
    let revision: Int
}

private struct StoredGalleryManifestPersistenceMutation: Sendable {
    let identifier: EHGalleryIdentifier
    let finalEntry: StoredGalleryEntry?
    let stagingEntry: StoredGalleryEntry?
    let revision: Int
}

private enum StoredGalleryManifestMutation: Sendable {
    case note(String?, updatedAt: Date)
    case metadata(title: String, thumbnailURL: URL?, totalPageCount: Int?, updatedAt: Date)
    case downloadUnavailable(title: String?, thumbnailURL: URL?, totalPageCount: Int?, updatedAt: Date)

    /// Applies a stable value mutation identically in the UI mirror and disk actor.
    func apply(to manifest: inout StoredGalleryManifest) {
        switch self {
        case let .note(note, updatedAt):
            manifest.note = note
            manifest.updatedAt = updatedAt
        case let .metadata(title, thumbnailURL, totalPageCount, updatedAt):
            manifest.title = title
            manifest.thumbnailURL = thumbnailURL ?? manifest.thumbnailURL
            manifest.totalPageCount = totalPageCount ?? manifest.totalPageCount
            manifest.updatedAt = updatedAt
            manifest.isDownloadUnavailable = false
        case let .downloadUnavailable(title, thumbnailURL, totalPageCount, updatedAt):
            manifest.title = title ?? manifest.title
            manifest.thumbnailURL = thumbnailURL ?? manifest.thumbnailURL
            manifest.totalPageCount = totalPageCount ?? manifest.totalPageCount
            manifest.updatedAt = updatedAt
            manifest.isDownloadUnavailable = true
        }
    }
}

private struct GalleryPreparationRequest: Sendable {
    let summary: CachedGallerySummary
    let finalEntry: StoredGalleryEntry?
    let stagingEntry: StoredGalleryEntry?
    let stagingRootURL: URL
    let manifestFilename: String
}

private struct GalleryFinalizationRequest: Sendable {
    let entry: StoredGalleryEntry
    let finalURL: URL
    let rootURL: URL
    let stagingRootURL: URL
    let manifestFilename: String
}

enum CachedGalleryStoreError: LocalizedError {
    case invalidPageContext
    case stagingNotPrepared
    case emptyGallery
    case incompleteGallery
    case missingPageFile

    var errorDescription: String? {
        switch self {
        case .invalidPageContext:
            "下载页面缺少图库或页码信息。"
        case .stagingNotPrepared:
            "图库永久存储尚未准备完成。"
        case .emptyGallery:
            "图库没有可保存的图片。"
        case .incompleteGallery:
            "图库页面尚未全部保存。"
        case .missingPageFile:
            "图库中存在缺失或损坏的图片文件。"
        }
    }
}
