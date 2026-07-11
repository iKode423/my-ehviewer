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
final class CachedGalleryStore: ObservableObject {
    static let shared = CachedGalleryStore()

    @Published private(set) var summaries: [CachedGallerySummary] = []

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

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        stagingRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? documentsURL.appending(path: "Cached Gallery", directoryHint: .isDirectory)
        self.stagingRootURL = stagingRootURL ?? applicationSupportURL.appending(
            path: "CachedGalleryStaging",
            directoryHint: .isDirectory
        )
        prepareDirectories()
        refresh()
    }

    /// Reloads finalized and interrupted gallery manifests from disk.
    func refresh() {
        finalEntriesByGalleryID = loadEntries(in: rootURL)
        stagingEntriesByGalleryID = loadEntries(in: stagingRootURL)
        rebuildActiveState()
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

    /// Updates notes in both finalized and staged manifests.
    func setNote(_ note: String?, for identifier: EHGalleryIdentifier) {
        updateManifest(identifier: identifier) { manifest in
            manifest.note = note
            manifest.updatedAt = Date()
        }
    }

    /// Updates gallery metadata without changing stored page files.
    func updateMetadata(detail: EHGalleryDetail, fallback: EHSearchResult?) {
        updateManifest(identifier: detail.identifier) { manifest in
            manifest.title = detail.title
            manifest.thumbnailURL = detail.coverURL ?? fallback?.thumbnailURL ?? manifest.thumbnailURL
            manifest.totalPageCount = detail.pageCount ?? manifest.totalPageCount
            manifest.updatedAt = Date()
            manifest.isDownloadUnavailable = false
        }
    }

    /// Marks a stored or staged gallery as unavailable for future resume attempts.
    func markDownloadUnavailable(
        _ identifier: EHGalleryIdentifier,
        title: String?,
        thumbnailURL: URL?,
        totalPageCount: Int?
    ) {
        updateManifest(identifier: identifier) { manifest in
            manifest.title = title ?? manifest.title
            manifest.thumbnailURL = thumbnailURL ?? manifest.thumbnailURL
            manifest.totalPageCount = totalPageCount ?? manifest.totalPageCount
            manifest.updatedAt = Date()
            manifest.isDownloadUnavailable = true
        }
    }

    /// Removes finalized and interrupted local files for one gallery.
    func deleteGallery(_ identifier: EHGalleryIdentifier) {
        let urls = [
            finalEntriesByGalleryID[identifier.id]?.folderURL,
            stagingEntriesByGalleryID[identifier.id]?.folderURL
        ].compactMap { $0 }
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
        refresh()
    }

    /// Prepares a clean staging folder while preserving verified interrupted pages.
    func prepareGallery(
        summary: CachedGallerySummary
    ) async throws {
        let finalEntry = finalEntriesByGalleryID[summary.galleryIdentifier.id]
        let stagingEntry = stagingEntriesByGalleryID[summary.galleryIdentifier.id]
        let request = GalleryPreparationRequest(
            summary: summary,
            finalEntry: finalEntry,
            stagingEntry: stagingEntry,
            stagingRootURL: stagingRootURL,
            manifestFilename: manifestFilename
        )
        _ = try await Task.detached(priority: .utility) {
            try Self.prepareGalleryOnDisk(request)
        }.value
        refresh()
    }

    /// Copies one cached page into the prepared staging gallery.
    func importCachedPage(_ input: CachedGalleryPageInput, identifier: EHGalleryIdentifier) async throws {
        guard var entry = stagingEntriesByGalleryID[identifier.id] else {
            throw CachedGalleryStoreError.stagingNotPrepared
        }
        let oldPage = entry.manifest.pages.first { $0.pageNumber == input.pageNumber }
        let filename = Self.pageFilename(
            pageNumber: input.pageNumber,
            sourceFileURL: input.sourceFileURL,
            imageURL: input.imageURL
        )
        let destinationURL = entry.folderURL.appending(path: filename, directoryHint: .notDirectory)
        try await Task.detached(priority: .utility) {
            try Self.copyFileReplacingExisting(from: input.sourceFileURL, to: destinationURL)
        }.value

        if let oldPage, oldPage.filename != filename {
            try? fileManager.removeItem(at: entry.folderURL.appending(path: oldPage.filename))
        }
        let byteCount = Self.fileSize(at: destinationURL)
        entry.manifest.pages.removeAll { $0.pageNumber == input.pageNumber }
        entry.manifest.pages.append(
            StoredGalleryPage(
                pageNumber: input.pageNumber,
                pageURL: input.pageURL,
                imageURL: input.imageURL,
                responseImageURL: nil,
                thumbnailURL: input.thumbnailURL,
                filename: filename,
                byteCount: byteCount,
                updatedAt: input.updatedAt
            )
        )
        entry.manifest.pages.sort { $0.pageNumber < $1.pageNumber }
        entry.manifest.updatedAt = Date()
        try writeManifest(entry.manifest, to: entry.folderURL)
        stagingEntriesByGalleryID[identifier.id] = entry
        rebuildActiveState()
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
        guard var entry = stagingEntriesByGalleryID[identifier.id] else {
            throw CachedGalleryStoreError.stagingNotPrepared
        }
        let filename = Self.pageFilename(
            pageNumber: pageNumber,
            data: data,
            imageURLs: [responseURL, requestedURL]
        )
        let destinationURL = entry.folderURL.appending(path: filename, directoryHint: .notDirectory)
        let oldPage = entry.manifest.pages.first { $0.pageNumber == pageNumber }
        try await Task.detached(priority: .utility) {
            try data.write(to: destinationURL, options: [.atomic])
        }.value

        if let oldPage, oldPage.filename != filename {
            try? fileManager.removeItem(at: entry.folderURL.appending(path: oldPage.filename))
        }
        entry.manifest.title = context.galleryTitle ?? entry.manifest.title
        entry.manifest.thumbnailURL = context.thumbnailURL ?? entry.manifest.thumbnailURL
        entry.manifest.totalPageCount = context.totalPageCount ?? entry.manifest.totalPageCount
        entry.manifest.updatedAt = Date()
        entry.manifest.pages.removeAll { $0.pageNumber == pageNumber }
        entry.manifest.pages.append(
            StoredGalleryPage(
                pageNumber: pageNumber,
                pageURL: pageURL,
                imageURL: requestedURL,
                responseImageURL: responseURL == requestedURL ? nil : responseURL,
                thumbnailURL: context.thumbnailURL,
                filename: filename,
                byteCount: Int64(data.count),
                updatedAt: Date()
            )
        )
        entry.manifest.pages.sort { $0.pageNumber < $1.pageNumber }
        try writeManifest(entry.manifest, to: entry.folderURL)
        stagingEntriesByGalleryID[identifier.id] = entry
        rebuildActiveState()
    }

    /// Finalizes a staged gallery only after every listed file passes verification.
    func finalizeGallery(_ identifier: EHGalleryIdentifier, requireComplete: Bool) async throws {
        guard var entry = stagingEntriesByGalleryID[identifier.id] else {
            throw CachedGalleryStoreError.stagingNotPrepared
        }
        let uniquePageCount = Set(entry.manifest.pages.map(\.pageNumber)).count
        if requireComplete,
           let totalPageCount = entry.manifest.totalPageCount,
           uniquePageCount < totalPageCount {
            throw CachedGalleryStoreError.incompleteGallery
        }
        entry.manifest.isComplete = entry.manifest.totalPageCount.map { uniquePageCount >= $0 } ?? false
        entry.manifest.updatedAt = Date()
        try writeManifest(entry.manifest, to: entry.folderURL)

        let finalURL = finalEntriesByGalleryID[identifier.id]?.folderURL
            ?? rootURL.appending(path: Self.folderName(for: entry.manifest), directoryHint: .isDirectory)
        let request = GalleryFinalizationRequest(
            entry: entry,
            finalURL: finalURL,
            rootURL: rootURL,
            stagingRootURL: stagingRootURL,
            manifestFilename: manifestFilename
        )
        try await Task.detached(priority: .utility) {
            try Self.finalizeGalleryOnDisk(request)
        }.value
        refresh()
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
                let currentByteCount = Self.fileSize(at: localFileURL)
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
                    storageState: records.isEmpty ? .cacheOnly : .persistent
                )
            )
        }

        pageRecordByPageURL = pageURLLookup
        pageRecordByGalleryPage = galleryPageLookup
        fileURLByImageURL = imageURLLookup
        summaries = rebuiltSummaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Updates a manifest in every storage location where it exists.
    private func updateManifest(
        identifier: EHGalleryIdentifier,
        mutation: (inout StoredGalleryManifest) -> Void
    ) {
        var changed = false
        if var finalEntry = finalEntriesByGalleryID[identifier.id] {
            mutation(&finalEntry.manifest)
            if (try? writeManifest(finalEntry.manifest, to: finalEntry.folderURL)) != nil {
                finalEntriesByGalleryID[identifier.id] = finalEntry
                changed = true
            }
        }
        if var stagingEntry = stagingEntriesByGalleryID[identifier.id] {
            mutation(&stagingEntry.manifest)
            if (try? writeManifest(stagingEntry.manifest, to: stagingEntry.folderURL)) != nil {
                stagingEntriesByGalleryID[identifier.id] = stagingEntry
                changed = true
            }
        }
        if changed {
            rebuildActiveState()
        }
    }

    /// Loads valid manifests from one gallery storage root.
    private func loadEntries(in directoryURL: URL) -> [String: StoredGalleryEntry] {
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
                let manifest = try? Self.decodeManifest(data)
            else {
                continue
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

    /// Writes a manifest atomically.
    private func writeManifest(_ manifest: StoredGalleryManifest, to folderURL: URL) throws {
        try Self.writeManifestStatic(manifest, to: folderURL, filename: manifestFilename)
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
    private static func decodeManifest(_ data: Data) throws -> StoredGalleryManifest {
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
    private static func pageFilename(pageNumber: Int, sourceFileURL: URL, imageURL: URL) -> String {
        let fileExtension = preferredFileExtension(sourceFileURL: sourceFileURL, imageURLs: [imageURL])
        return String(format: "%04d.%@", pageNumber, fileExtension)
    }

    /// Produces a numbered filename for freshly downloaded image data.
    private static func pageFilename(pageNumber: Int, data: Data, imageURLs: [URL]) -> String {
        let fileExtension = preferredFileExtension(data: data, imageURLs: imageURLs)
        return String(format: "%04d.%@", pageNumber, fileExtension)
    }

    /// Resolves an extension from ImageIO before using the remote path extension.
    private static func preferredFileExtension(sourceFileURL: URL, imageURLs: [URL]) -> String {
        if let source = CGImageSourceCreateWithURL(sourceFileURL as CFURL, nil),
           let type = CGImageSourceGetType(source),
           let extensionName = UTType(type as String)?.preferredFilenameExtension {
            return extensionName.lowercased()
        }
        return remoteFileExtension(imageURLs) ?? "img"
    }

    /// Resolves an extension from downloaded bytes before using the remote path extension.
    private static func preferredFileExtension(data: Data, imageURLs: [URL]) -> String {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source),
           let extensionName = UTType(type as String)?.preferredFilenameExtension {
            return extensionName.lowercased()
        }
        return remoteFileExtension(imageURLs) ?? "img"
    }

    /// Returns a conservative remote filename extension.
    private static func remoteFileExtension(_ imageURLs: [URL]) -> String? {
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
