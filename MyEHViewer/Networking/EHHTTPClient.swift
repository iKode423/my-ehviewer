import Combine
import CryptoKit
import Foundation

/// Represents a text response returned by the E-Hentai website.
struct EHHTTPResponse: Hashable {
    let url: URL
    let statusCode: Int
    let body: String
}

/// Represents a binary response returned by a remote image request.
struct EHDataResponse {
    let url: URL
    let statusCode: Int
    let data: Data
}

/// Describes failures that can happen while loading public website pages.
enum EHNetworkError: LocalizedError, Equatable {
    case invalidResponse
    case unacceptableStatusCode(Int)
    case undecodableBody

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器响应无效。"
        case .unacceptableStatusCode(let code):
            "服务器返回状态码 \(code)。"
        case .undecodableBody:
            "页面内容无法解码。"
        }
    }
}

private extension Error {
    /// Returns true when an HTTP response explicitly reports 404.
    var isHTTPNotFound: Bool {
        guard let networkError = self as? EHNetworkError else { return false }
        if case .unacceptableStatusCode(404) = networkError {
            return true
        }
        return false
    }
}

/// Loads public HTML pages while preserving cookies in the shared URL session.
@MainActor
protocol EHHTTPClient {
    /// Sends a GET request and returns the decoded HTML body.
    func get(_ url: URL) async throws -> EHHTTPResponse
}

/// Loads HTML and binary image data with the same cookie context.
@MainActor
protocol EHDataHTTPClient: EHHTTPClient {
    /// Sends a GET request and returns the raw binary response data.
    func data(_ url: URL) async throws -> EHDataResponse

    /// Sends a GET request for binary data with the page that referenced it.
    func data(_ url: URL, referer: URL?) async throws -> EHDataResponse
}

extension EHDataHTTPClient {
    /// Falls back to the plain binary request when a client does not support referers.
    func data(_ url: URL, referer: URL?) async throws -> EHDataResponse {
        try await data(url)
    }
}

/// Submits URL-encoded site forms while preserving cookies.
@MainActor
protocol EHFormHTTPClient {
    /// Sends a POST request and returns the decoded HTML body.
    func postForm(_ url: URL, fields: [String: String]) async throws -> EHHTTPResponse
}

/// Maps legacy Hitomi image URLs to the current CDN hosts used by the web app.
enum HitomiImageURLMigration {
    /// Returns the current CDN URL for legacy Hitomi thumbnail hosts.
    static func currentURL(for url: URL) -> URL {
        guard isLegacyThumbnailURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        components.scheme = "https"
        components.host = "tn.gold-usergeneratedcontent.net"
        return components.url ?? url
    }

    /// Returns URLs that should share one cached image file.
    static func equivalentURLs(for url: URL) -> [URL] {
        let currentURL = currentURL(for: url)
        return currentURL == url ? [url] : [url, currentURL]
    }

    /// Detects old thumbnail hosts that can fail TLS through some proxy routes.
    private static func isLegacyThumbnailURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "hitomi.la" || host.hasSuffix(".hitomi.la")
        else {
            return false
        }

        let pathPrefix = url.path.split(separator: "/", omittingEmptySubsequences: true).first
        return pathPrefix == "webpsmalltn" || pathPrefix == "avifsmalltn"
    }
}

/// Default URLSession-backed HTTP client used by the app.
@MainActor
final class URLSessionEHHTTPClient: EHDataHTTPClient, EHFormHTTPClient {
    /// Provides a shared browser-like session tuned for gallery image downloads.
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 12
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession
    private let cookieHeaderProvider: @MainActor () -> String?

    /// Creates a client with browser-like headers that the public site accepts.
    init(
        session: URLSession = URLSessionEHHTTPClient.defaultSession,
        cookieHeaderProvider: @escaping @MainActor () -> String? = { SiteCookieStore.shared.cookieHeaderForRequest }
    ) {
        self.session = session
        self.cookieHeaderProvider = cookieHeaderProvider
    }

    /// Sends a GET request using a stable user agent and Chinese language preference.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        let (data, httpResponse) = try await responseData(for: makeRequest(url, accept: "text/html,application/xhtml+xml"))

        if let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return EHHTTPResponse(url: httpResponse.url ?? url, statusCode: httpResponse.statusCode, body: body)
        }

        throw EHNetworkError.undecodableBody
    }

    /// Sends a GET request and returns the raw binary response data.
    func data(_ url: URL) async throws -> EHDataResponse {
        try await data(url, referer: EHConstants.baseURL)
    }

    /// Downloads binary data with a browser-like referer for image hosts.
    func data(_ url: URL, referer: URL?) async throws -> EHDataResponse {
        let requestURL = HitomiImageURLMigration.currentURL(for: url)
        let (data, httpResponse) = try await responseData(for: makeRequest(
            requestURL,
            accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            referer: referer ?? EHConstants.baseURL
        ))
        return EHDataResponse(url: httpResponse.url ?? requestURL, statusCode: httpResponse.statusCode, data: data)
    }

    /// Sends a URL-encoded POST request using the same browser-like headers.
    func postForm(_ url: URL, fields: [String: String]) async throws -> EHHTTPResponse {
        var request = makeRequest(url, accept: "text/html,application/xhtml+xml")
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)

        let (data, httpResponse) = try await responseData(for: request)
        if let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return EHHTTPResponse(url: httpResponse.url ?? url, statusCode: httpResponse.statusCode, body: body)
        }
        throw EHNetworkError.undecodableBody
    }

    /// Builds a browser-like request with optional site cookies.
    private func makeRequest(_ url: URL, accept: String, referer: URL? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 MyEHViewer/0.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        if shouldAttachSiteCookie(to: url), let cookieHeader = cookieHeaderProvider(), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    /// Returns true only for hosts that own the configured site cookie.
    private func shouldAttachSiteCookie(to url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "e-hentai.org" || host.hasSuffix(".e-hentai.org") || host == "exhentai.org" || host.hasSuffix(".exhentai.org")
    }

    /// Validates the URLSession response and returns the response data.
    private func responseData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EHNetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw EHNetworkError.unacceptableStatusCode(httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    /// Encodes form fields for a site POST body.
    private func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

/// Describes current disk usage for cached remote images.
struct ImageCacheSnapshot: Equatable {
    let fileCount: Int
    let byteCount: Int64
    let galleryCount: Int

    static let empty = ImageCacheSnapshot(fileCount: 0, byteCount: 0, galleryCount: 0)

    var isEmpty: Bool {
        fileCount == 0
    }

    var localizedByteCount: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// Carries gallery metadata when saving one reader image into cache.
struct ImageCacheContext: Hashable {
    let galleryIdentifier: EHGalleryIdentifier?
    let galleryTitle: String?
    let pageNumber: Int?
    let pageURL: URL?
    let totalPageCount: Int?
    let thumbnailURL: URL?
}

/// Stores one cached reader page mapping.
struct CachedImagePageRecord: Codable, Hashable, Identifiable, Sendable {
    let galleryIdentifier: EHGalleryIdentifier
    var galleryTitle: String
    var pageNumber: Int
    var pageURL: URL
    var imageURL: URL
    var cacheKey: String
    var byteCount: Int64
    var totalPageCount: Int?
    var thumbnailURL: URL?
    var updatedAt: Date
    var localFileURL: URL? = nil

    var id: String { "\(galleryIdentifier.id)-\(pageNumber)" }

    /// Returns whether this page is backed by durable gallery storage.
    var isPersistentlyStored: Bool {
        localFileURL != nil
    }
}

/// Describes whether a gallery only uses disposable cache files or durable storage.
enum CachedGalleryStorageState: Hashable, Sendable {
    case cacheOnly
    case persistent
}

/// Summarizes cached pages for one gallery.
struct CachedGallerySummary: Hashable, Identifiable, Sendable {
    let galleryIdentifier: EHGalleryIdentifier
    let title: String
    let note: String?
    let thumbnailURL: URL?
    let cachedPageCount: Int
    let totalPageCount: Int?
    let byteCount: Int64
    let updatedAt: Date
    let pageRecords: [CachedImagePageRecord]
    let isDownloadUnavailable: Bool
    let isStaged: Bool
    let isStagedComplete: Bool
    let storageState: CachedGalleryStorageState

    /// Creates a cache summary while keeping the 404 marker optional for older call sites.
    init(
        galleryIdentifier: EHGalleryIdentifier,
        title: String,
        note: String? = nil,
        thumbnailURL: URL?,
        cachedPageCount: Int,
        totalPageCount: Int?,
        byteCount: Int64,
        updatedAt: Date,
        pageRecords: [CachedImagePageRecord],
        isDownloadUnavailable: Bool = false,
        isStaged: Bool = false,
        isStagedComplete: Bool = false,
        storageState: CachedGalleryStorageState = .cacheOnly
    ) {
        self.galleryIdentifier = galleryIdentifier
        self.title = title
        self.note = note
        self.thumbnailURL = thumbnailURL
        self.cachedPageCount = cachedPageCount
        self.totalPageCount = totalPageCount
        self.byteCount = byteCount
        self.updatedAt = updatedAt
        self.pageRecords = pageRecords
        self.isDownloadUnavailable = isDownloadUnavailable
        self.isStaged = isStaged
        self.isStagedComplete = isStagedComplete
        self.storageState = storageState
    }

    var id: String { galleryIdentifier.id }

    var progressText: String {
        if let totalPageCount {
            return "已缓存 \(cachedPageCount)/\(totalPageCount) 页"
        }
        return "已缓存 \(cachedPageCount) 页"
    }

    var localizedByteCount: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// Returns whether missing pages or staged finalization still need background work.
    var needsDownloadResume: Bool {
        guard let totalPageCount else { return false }
        if isStagedComplete {
            return true
        }
        guard !isDownloadUnavailable else { return false }
        return cachedPageCount < totalPageCount || isStaged
    }

    var searchResult: EHSearchResult {
        EHSearchResult(
            identifier: galleryIdentifier,
            title: title,
            category: "",
            pageURL: galleryIdentifier.url(),
            thumbnailURL: thumbnailURL,
            uploader: nil,
            postedText: nil,
            pageCountText: totalPageCount.map { "\($0) pages" },
            tags: []
        )
    }
}

/// Stores viewed image data on disk so reader pages can reopen without refetching.
@MainActor
final class ImageCacheStore: ObservableObject {
    static let shared = ImageCacheStore(refreshesOnInit: false)

    @Published private(set) var snapshot: ImageCacheSnapshot = .empty
    @Published private(set) var gallerySummaries: [CachedGallerySummary] = []
    @Published private(set) var persistenceProgress: CachedGalleryPersistenceProgress?

    private let directoryURL: URL
    private let fileManager: FileManager
    private let persistentGalleryStore: CachedGalleryStore?
    private let afterCacheDataWriteEnqueued: @Sendable () async -> Void
    private let afterCacheFileWrite: @Sendable () async -> Void
    private let cacheWriteErrorHandler: (Error) -> Void
    private let indexFileName = "index.json"
    private var index = ImageCacheIndex()
    private var contentDigestByCacheKey: [String: String] = [:]
    private var cacheKeyByContentDigest: [String: String] = [:]
    private var cacheFileSizeByKey: [String: Int64] = [:]
    private var gallerySummaryByID: [String: CachedGallerySummary] = [:]
    private var pendingIndexSaveTask: Task<Void, Never>?
    private let diskWriter: ImageCacheDiskWriter
    private var pendingGallerySummaryRefreshTask: Task<Void, Never>?
    private var pendingPersistentGalleryRefreshTask: Task<Void, Never>?
    private var lastGallerySummaryRefreshAt = Date.distantPast
    private var lastDiskRefreshAt = Date.distantPast
    private let gallerySummaryRefreshInterval: TimeInterval = 1.0
    private let indexSaveDelayNanoseconds: UInt64 = 1_000_000_000
    private var deferredGallerySummaryRefreshDepth = 0
    private var cacheClearGeneration = 0
    private var cacheScopeGeneration: [String: Int] = [:]
    private var nextCacheWriteSequence: UInt64 = 0
    private var latestCacheWriteSequenceByKey: [String: UInt64] = [:]
    private var latestSuccessfulCacheWriteSequenceByKey: [String: UInt64] = [:]
    private var pendingCacheWriteByID: [UUID: ImageCachePendingWrite] = [:]

    /// Creates a cache store rooted in the app caches directory by default.
    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        persistentGalleryStore: CachedGalleryStore? = nil,
        refreshesOnInit: Bool = true,
        afterCacheDataWriteEnqueued: @escaping @Sendable () async -> Void = {},
        afterCacheFileWrite: @escaping @Sendable () async -> Void = {},
        beforeCacheDiskMutation: @escaping @Sendable () -> Void = {},
        beforeCacheDataWrite: @escaping @Sendable () throws -> Void = {},
        cacheWriteErrorHandler: @escaping (Error) -> Void = { error in
            assertionFailure("Failed to save image cache: \(error.localizedDescription)")
        }
    ) {
        self.fileManager = fileManager
        self.persistentGalleryStore = persistentGalleryStore ?? (directoryURL == nil ? .shared : nil)
        self.afterCacheDataWriteEnqueued = afterCacheDataWriteEnqueued
        self.afterCacheFileWrite = afterCacheFileWrite
        self.cacheWriteErrorHandler = cacheWriteErrorHandler
        diskWriter = ImageCacheDiskWriter(
            beforeMutation: beforeCacheDiskMutation,
            beforeDataWrite: beforeCacheDataWrite
        )
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
            self.directoryURL = baseURL.appending(path: "ImageCache", directoryHint: .isDirectory)
        }
        loadIndex()
        if refreshesOnInit {
            refresh(compactsDuplicates: false)
        } else {
            publishGallerySummaries()
            schedulePersistentGalleryRefresh()
        }
    }

    /// Returns cached image data for the remote URL when it exists.
    func data(for url: URL) -> Data? {
        guard let fileURL = cachedDataFileURL(for: url) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    /// Returns true when image data exists for a URL.
    func containsData(for url: URL) -> Bool {
        cachedDataFileURL(for: url) != nil
    }

    /// Returns the local cache file URL for a remote image URL when bytes exist.
    func cachedDataFileURL(for url: URL) -> URL? {
        if let persistentFileURL = persistentGalleryStore?.fileURL(for: url) {
            return persistentFileURL
        }
        for candidateURL in HitomiImageURLMigration.equivalentURLs(for: url) {
            if let cacheKey = index.aliases[candidateURL.absoluteString] {
                let fileURL = fileURL(forKey: cacheKey)
                if fileManager.fileExists(atPath: fileURL.path) {
                    return fileURL
                }
            }

            let legacyURL = legacyFileURL(for: candidateURL)
            if fileManager.fileExists(atPath: legacyURL.path) {
                return legacyURL
            }
        }

        return nil
    }

    /// Returns a cached reader page for a specific reader URL.
    func pageRecord(for pageURL: URL) -> CachedImagePageRecord? {
        persistentGalleryStore?.pageRecord(for: pageURL)
            ?? index.pages.values.first { $0.pageURL == pageURL }
    }

    /// Returns a cached reader page for a gallery page number.
    func pageRecord(for identifier: EHGalleryIdentifier, pageNumber: Int) -> CachedImagePageRecord? {
        persistentGalleryStore?.pageRecord(for: identifier, pageNumber: pageNumber)
            ?? index.pages[pageKey(identifier: identifier, pageNumber: pageNumber)]
    }

    /// Returns the cached image URL for a gallery page when the image bytes are available.
    func cachedImageURL(for identifier: EHGalleryIdentifier, pageNumber: Int) -> URL? {
        guard
            let record = pageRecord(for: identifier, pageNumber: pageNumber),
            containsData(for: record.imageURL)
        else {
            return nil
        }
        return record.imageURL
    }

    /// Defers expensive gallery summary rebuilds while a download batch writes many pages.
    func beginDeferredGallerySummaryRefreshes() {
        deferredGallerySummaryRefreshDepth += 1
    }

    /// Ends one gallery batch and publishes its summary before releasing the download task.
    func endDeferredGallerySummaryRefreshes(for identifier: EHGalleryIdentifier) async {
        deferredGallerySummaryRefreshDepth = max(0, deferredGallerySummaryRefreshDepth - 1)
        if deferredGallerySummaryRefreshDepth == 0 {
            await flushPendingIndexSaveAsync()
            publishGallerySummaries()
        } else {
            publishGallerySummary(for: identifier)
        }
    }

    /// Returns the cached gallery summary using the in-memory lookup table.
    func gallerySummary(for identifier: EHGalleryIdentifier) -> CachedGallerySummary? {
        gallerySummaryByID[identifier.id]
    }

    /// Returns whether durable staging already contains every expected page.
    func hasCompletePersistentStaging(for identifier: EHGalleryIdentifier) -> Bool {
        persistentGalleryStore?.hasCompleteStagedGallery(identifier) ?? false
    }

    /// Skips the expensive disk scan when the cache was refreshed recently.
    func refreshIfNeeded(minimumInterval: TimeInterval = 300, compactsDuplicates: Bool = false) {
        guard deferredGallerySummaryRefreshDepth == 0,
              Date().timeIntervalSince(lastDiskRefreshAt) >= minimumInterval
        else {
            return
        }
        refresh(compactsDuplicates: compactsDuplicates)
    }

    /// Refreshes cache file metadata off the main actor when duplicate compaction is not requested.
    func refreshIfNeededAsync(minimumInterval: TimeInterval = 300) async {
        guard deferredGallerySummaryRefreshDepth == 0,
              Date().timeIntervalSince(lastDiskRefreshAt) >= minimumInterval
        else {
            return
        }
        await refreshAsync()
    }

    /// Scans cache files on a utility executor and rejects results made stale by writes or clears.
    func refreshAsync() async {
        pendingGallerySummaryRefreshTask?.cancel()
        pendingGallerySummaryRefreshTask = nil
        let claimedWriteSequence = nextCacheWriteSequence
        let claimedClearGeneration = cacheClearGeneration
        let claimedScopeGenerations = cacheScopeGeneration
        let directoryURL = directoryURL
        let indexFileName = indexFileName
        let snapshot = await Task.detached(priority: .utility) {
            Self.scanCacheDirectory(
                directoryURL: directoryURL,
                indexFileName: indexFileName
            )
        }.value
        guard claimedWriteSequence == nextCacheWriteSequence,
              claimedClearGeneration == cacheClearGeneration,
              claimedScopeGenerations == cacheScopeGeneration
        else {
            return
        }

        schedulePersistentGalleryRefresh()
        cacheFileSizeByKey = snapshot.fileSizeByKey
        let validCacheKeys = Set(snapshot.fileSizeByKey.keys)
        contentDigestByCacheKey = contentDigestByCacheKey.filter { validCacheKeys.contains($0.key) }
        rebuildContentDigestLookup()
        if removeMissingIndexEntries(validCacheKeys: validCacheKeys) {
            saveIndex()
        }
        setGallerySummaries(makeGallerySummaries())
        lastGallerySummaryRefreshAt = Date()
        lastDiskRefreshAt = Date()
        self.snapshot = ImageCacheSnapshot(
            fileCount: snapshot.fileSizeByKey.count,
            byteCount: snapshot.byteCount,
            galleryCount: gallerySummaries.count
        )
    }

    /// Stores gallery metadata so cache management can list partially downloaded galleries.
    func saveGalleryMetadata(detail: EHGalleryDetail, fallback: EHSearchResult? = nil) {
        applyGalleryMetadata(detail: detail, fallback: fallback)
        saveIndex()
        publishGallerySummaries()
    }

    /// Persists download metadata without waiting on index I/O from MainActor.
    func saveGalleryMetadataForDownload(detail: EHGalleryDetail, fallback: EHSearchResult? = nil) async {
        applyGalleryMetadata(detail: detail, fallback: fallback)
        if deferredGallerySummaryRefreshDepth == 0 {
            publishGallerySummaries()
        }
        await saveIndexAsync()
    }

    /// Applies one gallery metadata change to the cache projection.
    private func applyGalleryMetadata(detail: EHGalleryDetail, fallback: EHSearchResult?) {
        let existing = index.galleryMetadata[detail.identifier.id]
        index.galleryMetadata[detail.identifier.id] = CachedGalleryMetadata(
            identifier: detail.identifier,
            title: detail.title,
            note: existing?.note,
            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL,
            totalPageCount: detail.pageCount,
            updatedAt: Date(),
            isDownloadUnavailable: false
        )
        persistentGalleryStore?.updateMetadata(detail: detail, fallback: fallback)
    }

    /// Returns the custom cache note for a gallery.
    func note(for identifier: EHGalleryIdentifier) -> String? {
        persistentGalleryStore?.note(for: identifier)
            ?? index.galleryMetadata[identifier.id]?.note
    }

    /// Updates the user-defined note for a cached gallery.
    func setGalleryNote(_ note: String, for identifier: EHGalleryIdentifier) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = index.galleryMetadata[identifier.id]
        let records = index.pages.values.filter { $0.galleryIdentifier == identifier }
        let storedNote = persistentGalleryStore?.note(for: identifier)
        guard existing != nil || !records.isEmpty || storedNote != nil || gallerySummary(for: identifier) != nil else { return }

        persistentGalleryStore?.setNote(trimmedNote.isEmpty ? nil : trimmedNote, for: identifier)

        if existing != nil || !records.isEmpty {
            index.galleryMetadata[identifier.id] = CachedGalleryMetadata(
                identifier: identifier,
                title: existing?.title ?? records.first?.galleryTitle ?? "图库 \(identifier.gid)",
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                thumbnailURL: existing?.thumbnailURL ?? records.first?.thumbnailURL,
                totalPageCount: existing?.totalPageCount ?? records.compactMap(\.totalPageCount).max(),
                updatedAt: Date(),
                isDownloadUnavailable: existing?.isDownloadUnavailable ?? false
            )
        }
        saveIndex()
        publishGallerySummaries()
    }

    /// Permanently saves every gallery that still owns image-cache files.
    func persistAllCachedGalleries() async throws -> Int {
        guard let persistentGalleryStore else { return 0 }
        let cacheSummaries = makeCacheGallerySummaries().filter { !$0.pageRecords.isEmpty }
        guard !cacheSummaries.isEmpty else { return 0 }

        persistenceProgress = CachedGalleryPersistenceProgress(
            completedGalleryCount: 0,
            totalGalleryCount: cacheSummaries.count,
            currentTitle: cacheSummaries[0].title
        )
        defer { persistenceProgress = nil }

        var completedCount = 0
        for summary in cacheSummaries {
            let pageInputs = cachedPageInputs(for: summary)
            guard !pageInputs.isEmpty else { continue }
            persistenceProgress = CachedGalleryPersistenceProgress(
                completedGalleryCount: completedCount,
                totalGalleryCount: cacheSummaries.count,
                currentTitle: summary.title
            )
            try await persistentGalleryStore.prepareGallery(summary: summary)
            try await persistentGalleryStore.importCachedPages(
                pageInputs,
                identifier: summary.galleryIdentifier
            )
            try await persistentGalleryStore.finalizeGallery(summary.galleryIdentifier, requireComplete: false)
            await removeCachedGalleryDataAsync(summary.galleryIdentifier, removesMetadata: true)
            completedCount += 1
            persistenceProgress = CachedGalleryPersistenceProgress(
                completedGalleryCount: completedCount,
                totalGalleryCount: cacheSummaries.count,
                currentTitle: summary.title
            )
        }
        publishGallerySummaries()
        return completedCount
    }

    /// Prepares durable staging before an explicit gallery download starts.
    func preparePersistentDownload(detail: EHGalleryDetail, fallback: EHSearchResult?) async throws {
        guard let persistentGalleryStore else { return }
        let cacheSummary = makeCacheGallerySummaries().first { $0.galleryIdentifier == detail.identifier }
        let summary = CachedGallerySummary(
            galleryIdentifier: detail.identifier,
            title: detail.title,
            note: cacheSummary?.note ?? note(for: detail.identifier),
            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL ?? cacheSummary?.thumbnailURL,
            cachedPageCount: cacheSummary?.cachedPageCount ?? 0,
            totalPageCount: detail.pageCount ?? cacheSummary?.totalPageCount,
            byteCount: cacheSummary?.byteCount ?? 0,
            updatedAt: Date(),
            pageRecords: cacheSummary?.pageRecords ?? [],
            isDownloadUnavailable: false
        )
        let pageInputs = cachedPageInputs(for: summary)
        try await persistentGalleryStore.prepareGallery(summary: summary)
        try await persistentGalleryStore.importCachedPages(pageInputs, identifier: detail.identifier)
        if deferredGallerySummaryRefreshDepth == 0 {
            publishGallerySummaries()
        }
    }

    /// Saves an explicit download into permanent staging instead of disposable cache storage.
    func saveDownloadedPageAsync(
        _ data: Data,
        for requestedURL: URL,
        responseURL: URL,
        context: ImageCacheContext
    ) async throws {
        if let persistentGalleryStore {
            try await persistentGalleryStore.saveDownloadedPage(
                data,
                requestedURL: requestedURL,
                responseURL: responseURL,
                context: context
            )
            if deferredGallerySummaryRefreshDepth == 0 {
                publishGallerySummaries()
            }
        } else {
            await saveAsync(data, for: requestedURL, responseURL: responseURL, context: context)
        }
    }

    /// Commits a complete explicit download and removes duplicate cache files.
    func finalizePersistentDownload(_ identifier: EHGalleryIdentifier) async throws {
        guard let persistentGalleryStore else { return }
        try await persistentGalleryStore.finalizeGallery(identifier, requireComplete: true)
        await removeCachedGalleryDataAsync(identifier, removesMetadata: true)
        if deferredGallerySummaryRefreshDepth == 0 {
            publishGallerySummaries()
        }
    }

    /// Marks a cached gallery as unavailable for future bulk download resumes.
    func markGalleryDownloadUnavailable(
        _ identifier: EHGalleryIdentifier,
        title: String? = nil,
        thumbnailURL: URL? = nil,
        totalPageCount: Int? = nil
    ) async {
        let existing = index.galleryMetadata[identifier.id]
        persistentGalleryStore?.markDownloadUnavailable(
            identifier,
            title: title,
            thumbnailURL: thumbnailURL,
            totalPageCount: totalPageCount
        )
        index.galleryMetadata[identifier.id] = CachedGalleryMetadata(
            identifier: identifier,
            title: title ?? existing?.title ?? "图库 \(identifier.gid)",
            note: existing?.note,
            thumbnailURL: thumbnailURL ?? existing?.thumbnailURL,
            totalPageCount: totalPageCount ?? existing?.totalPageCount,
            updatedAt: Date(),
            isDownloadUnavailable: true
        )
        await saveIndexAsync()
        if deferredGallerySummaryRefreshDepth == 0 {
            publishGallerySummaries()
        }
    }

    /// Saves image data and refreshes cache usage stats.
    func save(_ data: Data, for url: URL) {
        save(data, for: url, responseURL: url, context: nil)
    }

    /// Saves image data with aliases and optional gallery page metadata.
    func save(_ data: Data, for requestedURL: URL, responseURL: URL, context: ImageCacheContext?) {
        let mutationToken = beginCacheWrite(context: context)
        defer { endCacheWrite(mutationToken) }

        do {
            let dataDigest = contentDigest(for: data)
            let cacheKey = cacheKeyForAsyncSave(
                requestedURL: requestedURL,
                responseURL: responseURL,
                matchingDigest: dataDigest
            )
            guard let replacesExisting = claimCacheWriteOwnership(
                mutationToken,
                cacheKey: cacheKey,
                dataDigest: dataDigest
            ) else {
                return
            }
            let storedByteCount = try diskWriter.writeDataSynchronously(
                data,
                to: fileURL(forKey: cacheKey),
                replacesExisting: replacesExisting
            )
            recordSuccessfulCacheWrite(mutationToken, cacheKey: cacheKey)
            guard isLatestSuccessfulCacheWrite(mutationToken, cacheKey: cacheKey) else {
                removeUnreferencedCacheFileIfNeeded(
                    at: fileURL(forKey: cacheKey),
                    cacheKey: cacheKey,
                    excluding: mutationToken.id
                )
                return
            }

            storeContentDigest(dataDigest, cacheKey: cacheKey)
            storeAliases(for: cacheAliasURLs(requestedURL: requestedURL, responseURL: responseURL), cacheKey: cacheKey)
            upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: storedByteCount)
            saveIndexAfterCacheMutation()
            refreshAfterSaving(cacheKey: cacheKey, byteCount: storedByteCount, context: context)
        } catch {
            releaseFailedCacheWriteClaim(mutationToken)
            cacheWriteErrorHandler(error)
        }
    }

    /// Saves image data while moving disk writes off the main actor for async callers.
    func saveAsync(_ data: Data, for requestedURL: URL, responseURL: URL, context: ImageCacheContext?) async {
        let mutationToken = beginCacheWrite(context: context)
        defer { endCacheWrite(mutationToken) }
        var claimedCacheKey: String?

        do {
            let dataDigest = await Self.contentDigestAsync(for: data)
            guard isCurrentCacheWrite(mutationToken) else { return }
            let cacheKey = cacheKeyForAsyncSave(
                requestedURL: requestedURL,
                responseURL: responseURL,
                matchingDigest: dataDigest
            )
            guard let replacesExisting = claimCacheWriteOwnership(
                mutationToken,
                cacheKey: cacheKey,
                dataDigest: dataDigest
            ) else {
                return
            }
            claimedCacheKey = cacheKey

            let destinationURL = fileURL(forKey: cacheKey)
            let pendingWrite = diskWriter.enqueueDataWrite(
                data,
                to: destinationURL,
                replacesExisting: replacesExisting
            )
            await afterCacheDataWriteEnqueued()
            let storedByteCount = try await pendingWrite.value
            guard mutationToken.clearGeneration == cacheClearGeneration else { return }
            recordSuccessfulCacheWrite(mutationToken, cacheKey: cacheKey)
            guard mutationToken.scopeGeneration == cacheScopeGeneration[mutationToken.scopeID, default: 0] else {
                reconcileStaleSuccessfulCacheWrite(
                    mutationToken,
                    dataDigest: dataDigest,
                    storedByteCount: storedByteCount,
                    cacheKey: cacheKey,
                    fileURL: destinationURL
                )
                return
            }
            await afterCacheFileWrite()
            guard mutationToken.clearGeneration == cacheClearGeneration else { return }
            guard mutationToken.scopeGeneration == cacheScopeGeneration[mutationToken.scopeID, default: 0] else {
                reconcileStaleSuccessfulCacheWrite(
                    mutationToken,
                    dataDigest: dataDigest,
                    storedByteCount: storedByteCount,
                    cacheKey: cacheKey,
                    fileURL: destinationURL
                )
                return
            }
            guard isLatestSuccessfulCacheWrite(mutationToken, cacheKey: cacheKey) else {
                removeUnreferencedCacheFileIfNeeded(
                    at: destinationURL,
                    cacheKey: cacheKey,
                    excluding: mutationToken.id
                )
                return
            }

            storeContentDigest(dataDigest, cacheKey: cacheKey)
            storeAliases(for: cacheAliasURLs(requestedURL: requestedURL, responseURL: responseURL), cacheKey: cacheKey)
            upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: storedByteCount)
            saveIndexAfterCacheMutation()
            refreshAfterSaving(cacheKey: cacheKey, byteCount: storedByteCount, context: context)
        } catch {
            if claimedCacheKey != nil {
                releaseFailedCacheWriteClaim(mutationToken)
            }
            guard isCurrentCacheWrite(mutationToken) else { return }
            cacheWriteErrorHandler(error)
        }
    }

    /// Adds gallery page metadata for bytes that already exist in the cache.
    func recordExistingData(for requestedURL: URL, responseURL: URL, byteCount: Int64, context: ImageCacheContext?) {
        guard
            let fileURL = cachedDataFileURL(for: responseURL) ?? cachedDataFileURL(for: requestedURL)
        else {
            return
        }

        let cacheKey = fileURL.lastPathComponent
        storeAliases(for: cacheAliasURLs(requestedURL: requestedURL, responseURL: responseURL), cacheKey: cacheKey)
        upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: byteCount)
        saveIndexAfterCacheMutation()
        refreshAfterSaving(cacheKey: cacheKey, byteCount: byteCount, context: context)
    }

    /// Removes all cached image files from disk.
    func clear() {
        cacheClearGeneration += 1
        cacheScopeGeneration.removeAll()
        pendingIndexSaveTask?.cancel()
        pendingIndexSaveTask = nil
        if fileManager.fileExists(atPath: directoryURL.path) {
            diskWriter.removeDirectorySynchronously(directoryURL)
        }
        index = ImageCacheIndex()
        contentDigestByCacheKey = [:]
        cacheKeyByContentDigest = [:]
        cacheFileSizeByKey = [:]
        latestCacheWriteSequenceByKey = [:]
        latestSuccessfulCacheWriteSequenceByKey = [:]
        pendingCacheWriteByID = [:]
        schedulePersistentGalleryRefresh()
        setGallerySummaries(makeGallerySummaries())
        snapshot = ImageCacheSnapshot(
            fileCount: 0,
            byteCount: 0,
            galleryCount: gallerySummaries.count
        )
        lastDiskRefreshAt = Date()
        saveIndex()
    }

    /// Removes cached image files and page records for one gallery.
    func clearGallery(_ identifier: EHGalleryIdentifier) {
        advanceCacheScopeGeneration(for: identifier)
        persistentGalleryStore?.deleteGallery(identifier)
        removeCachedGalleryData(identifier, removesMetadata: true)
        publishGallerySummaries()
    }

    /// Removes disposable cache files while optionally preserving indexed metadata.
    private func removeCachedGalleryData(_ identifier: EHGalleryIdentifier, removesMetadata: Bool) {
        let removal = removeCachedGalleryProjection(identifier, removesMetadata: removesMetadata)
        guard removal.didChange else { return }
        diskWriter.writeSynchronously(
            index,
            to: indexURL,
            directoryURL: directoryURL,
            removing: removal.removableCacheKeys.map(fileURL(forKey:))
        )
    }

    /// Removes disposable gallery data without blocking MainActor on file or index I/O.
    private func removeCachedGalleryDataAsync(
        _ identifier: EHGalleryIdentifier,
        removesMetadata: Bool
    ) async {
        advanceCacheScopeGeneration(for: identifier)
        let removal = removeCachedGalleryProjection(identifier, removesMetadata: removesMetadata)
        guard removal.didChange else { return }

        let pendingWrite = diskWriter.enqueueWrite(
            index,
            to: indexURL,
            directoryURL: directoryURL,
            removing: removal.removableCacheKeys.map(fileURL(forKey:))
        )
        await pendingWrite.value
    }

    /// Applies one gallery removal to the in-memory cache projection and usage snapshot.
    private func removeCachedGalleryProjection(
        _ identifier: EHGalleryIdentifier,
        removesMetadata: Bool
    ) -> ImageCacheGalleryRemoval {
        let removedRecords = index.pages.values.filter { $0.galleryIdentifier == identifier }
        let removesStoredMetadata = removesMetadata && index.galleryMetadata[identifier.id] != nil
        guard !removedRecords.isEmpty || removesStoredMetadata else {
            return ImageCacheGalleryRemoval(removableCacheKeys: [], didChange: false)
        }

        let removedCacheKeys = Set(removedRecords.map(\.cacheKey))
        index.pages = index.pages.filter { $0.value.galleryIdentifier != identifier }
        if removesMetadata {
            index.galleryMetadata[identifier.id] = nil
        }

        let remainingCacheKeys = Set(index.pages.values.map(\.cacheKey))
            .union(currentPendingCacheKeys())
        let removableCacheKeys = removedCacheKeys.subtracting(remainingCacheKeys)
        index.aliases = index.aliases.filter { !removableCacheKeys.contains($0.value) }
        let removedByteCount = removableCacheKeys.reduce(Int64(0)) { total, cacheKey in
            total + (cacheFileSizeByKey[cacheKey] ?? 0)
        }
        for cacheKey in removableCacheKeys {
            if let digest = contentDigestByCacheKey.removeValue(forKey: cacheKey) {
                cacheKeyByContentDigest[digest] = nil
            }
            cacheFileSizeByKey[cacheKey] = nil
        }
        snapshot = ImageCacheSnapshot(
            fileCount: max(0, snapshot.fileCount - removableCacheKeys.count),
            byteCount: max(0, snapshot.byteCount - removedByteCount),
            galleryCount: gallerySummaries.count
        )
        return ImageCacheGalleryRemoval(
            removableCacheKeys: removableCacheKeys,
            didChange: true
        )
    }

    /// Returns true when cached image files are not tied to gallery reader pages.
    var hasNonGalleryImageCache: Bool {
        !nonGalleryCacheKeys().isEmpty
    }

    /// Removes search thumbnails, covers, and other image files not indexed as gallery pages.
    func clearNonGalleryImages() {
        cacheScopeGeneration[Self.nonGalleryCacheScopeID, default: 0] += 1
        let removableCacheKeys = nonGalleryCacheKeys()
        guard !removableCacheKeys.isEmpty else { return }

        index.aliases = index.aliases.filter { !removableCacheKeys.contains($0.value) }
        let removedByteCount = removableCacheKeys.reduce(Int64(0)) { total, cacheKey in
            total + (cacheFileSizeByKey[cacheKey] ?? 0)
        }
        for cacheKey in removableCacheKeys {
            if let digest = contentDigestByCacheKey.removeValue(forKey: cacheKey) {
                cacheKeyByContentDigest[digest] = nil
            }
            cacheFileSizeByKey[cacheKey] = nil
        }

        snapshot = ImageCacheSnapshot(
            fileCount: max(0, snapshot.fileCount - removableCacheKeys.count),
            byteCount: max(0, snapshot.byteCount - removedByteCount),
            galleryCount: gallerySummaries.count
        )
        diskWriter.writeSynchronously(
            index,
            to: indexURL,
            directoryURL: directoryURL,
            removing: removableCacheKeys.map(fileURL(forKey:))
        )
    }

    /// Recomputes cache usage stats from disk.
    func refresh(compactsDuplicates: Bool = false) {
        pendingGallerySummaryRefreshTask?.cancel()
        pendingGallerySummaryRefreshTask = nil
        lastGallerySummaryRefreshAt = Date()
        schedulePersistentGalleryRefresh()

        guard let allFileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            contentDigestByCacheKey = [:]
            cacheKeyByContentDigest = [:]
            cacheFileSizeByKey = [:]
            setGallerySummaries(makeGallerySummaries())
            snapshot = ImageCacheSnapshot(
                fileCount: 0,
                byteCount: 0,
                galleryCount: gallerySummaries.count
            )
            lastDiskRefreshAt = Date()
            return
        }

        let fileURLs = allFileURLs.filter { $0.lastPathComponent != indexFileName }
        var canonicalKeysByDigest: [String: String] = [:]
        var duplicateKeyMap: [String: String] = [:]
        var uniqueFileCount = 0
        var uniqueByteCount: Int64 = 0
        var refreshedFileSizes: [String: Int64] = [:]
        for fileURL in fileURLs {
            let cacheKey = fileURL.lastPathComponent
            if compactsDuplicates {
                guard let digest = contentDigest(for: fileURL) else { continue }
                if let canonicalKey = canonicalKeysByDigest[digest] {
                    duplicateKeyMap[cacheKey] = canonicalKey
                    try? fileManager.removeItem(at: fileURL)
                    continue
                }
                canonicalKeysByDigest[digest] = cacheKey
                contentDigestByCacheKey[cacheKey] = digest
                cacheKeyByContentDigest[digest] = cacheKey
            }
            uniqueFileCount += 1
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(values?.fileSize ?? 0)
            refreshedFileSizes[cacheKey] = fileSize
            uniqueByteCount += fileSize
        }
        if !duplicateKeyMap.isEmpty {
            remapIndexCacheKeys(duplicateKeyMap)
        }
        let validCacheKeys = compactsDuplicates ? Set(canonicalKeysByDigest.values) : Set(fileURLs.map(\.lastPathComponent))
        cacheFileSizeByKey = refreshedFileSizes.filter { validCacheKeys.contains($0.key) }
        contentDigestByCacheKey = contentDigestByCacheKey.filter { validCacheKeys.contains($0.key) }
        rebuildContentDigestLookup()
        let removedMissingEntries = removeMissingIndexEntries(validCacheKeys: validCacheKeys)
        if !duplicateKeyMap.isEmpty || removedMissingEntries {
            saveIndex()
        }
        setGallerySummaries(makeGallerySummaries())
        lastDiskRefreshAt = Date()
        snapshot = ImageCacheSnapshot(fileCount: uniqueFileCount, byteCount: uniqueByteCount, galleryCount: gallerySummaries.count)
    }

    /// Reads cache file sizes without touching MainActor-owned index state.
    nonisolated private static func scanCacheDirectory(
        directoryURL: URL,
        indexFileName: String
    ) -> ImageCacheDirectorySnapshot {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ImageCacheDirectorySnapshot(fileSizeByKey: [:], byteCount: 0)
        }
        var fileSizeByKey: [String: Int64] = [:]
        var byteCount: Int64 = 0
        for fileURL in fileURLs where fileURL.lastPathComponent != indexFileName {
            let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            fileSizeByKey[fileURL.lastPathComponent] = size
            byteCount += size
        }
        return ImageCacheDirectorySnapshot(fileSizeByKey: fileSizeByKey, byteCount: byteCount)
    }

    /// Adds or updates the page index when reader page metadata is available.
    private func upsertPageRecord(context: ImageCacheContext?, requestedURL: URL, responseURL: URL, cacheKey: String, byteCount: Int64) {
        guard
            let context,
            let identifier = context.galleryIdentifier,
            let pageNumber = context.pageNumber,
            let pageURL = context.pageURL
        else {
            return
        }

        let key = pageKey(identifier: identifier, pageNumber: pageNumber)
        let metadata = index.galleryMetadata[identifier.id]
        let title = context.galleryTitle ?? metadata?.title ?? "图库 \(identifier.gid)"
        let thumbnailURL = context.thumbnailURL ?? metadata?.thumbnailURL
        index.pages[key] = CachedImagePageRecord(
            galleryIdentifier: identifier,
            galleryTitle: title,
            pageNumber: pageNumber,
            pageURL: pageURL,
            imageURL: responseURL,
            cacheKey: cacheKey,
            byteCount: byteCount,
            totalPageCount: context.totalPageCount ?? metadata?.totalPageCount,
            thumbnailURL: thumbnailURL,
            updatedAt: Date()
        )
        index.galleryMetadata[identifier.id] = CachedGalleryMetadata(
            identifier: identifier,
            title: title,
            note: metadata?.note,
            thumbnailURL: thumbnailURL,
            totalPageCount: context.totalPageCount ?? metadata?.totalPageCount,
            updatedAt: Date(),
            isDownloadUnavailable: metadata?.isDownloadUnavailable ?? false
        )
        storeAliases(for: cacheAliasURLs(requestedURL: requestedURL, responseURL: responseURL), cacheKey: cacheKey)
    }

    /// Builds summaries from disposable cache index records only.
    private func makeCacheGallerySummaries() -> [CachedGallerySummary] {
        Dictionary(grouping: Array(index.pages.values), by: \.galleryIdentifier)
            .compactMap { identifier, records in
                makeCacheGallerySummary(for: identifier, records: records)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Builds one disposable cache summary without rebuilding unrelated galleries.
    private func makeCacheGallerySummary(
        for identifier: EHGalleryIdentifier,
        records: [CachedImagePageRecord]
    ) -> CachedGallerySummary? {
        guard !records.isEmpty else { return nil }
        let metadata = index.galleryMetadata[identifier.id]
        let sortedRecords = records.sorted { $0.pageNumber < $1.pageNumber }
        let uniqueCacheKeys = Set(records.map(\.cacheKey))
        let byteCount = uniqueCacheKeys.reduce(Int64(0)) { total, cacheKey in
            total + (cacheFileSizeByKey[cacheKey] ?? 0)
        }
        return CachedGallerySummary(
            galleryIdentifier: identifier,
            title: metadata?.title ?? records.first?.galleryTitle ?? "图库 \(identifier.gid)",
            note: metadata?.note,
            thumbnailURL: metadata?.thumbnailURL ?? records.first?.thumbnailURL,
            cachedPageCount: Set(records.map(\.pageNumber)).count,
            totalPageCount: metadata?.totalPageCount ?? records.compactMap(\.totalPageCount).max(),
            byteCount: byteCount,
            updatedAt: records.map(\.updatedAt).max() ?? metadata?.updatedAt ?? .distantPast,
            pageRecords: sortedRecords,
            isDownloadUnavailable: metadata?.isDownloadUnavailable ?? false,
            storageState: .cacheOnly
        )
    }

    /// Merges permanent gallery files with any cache pages not migrated yet.
    private func makeGallerySummaries() -> [CachedGallerySummary] {
        var summariesByID = Dictionary(
            uniqueKeysWithValues: makeCacheGallerySummaries().map { ($0.galleryIdentifier.id, $0) }
        )
        for storedSummary in persistentGalleryStore?.summaries ?? [] {
            summariesByID[storedSummary.galleryIdentifier.id] = mergeGallerySummary(
                cacheSummary: summariesByID[storedSummary.galleryIdentifier.id],
                storedSummary: storedSummary
            )
        }
        return summariesByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Builds one merged cache and permanent summary for a gallery boundary publication.
    private func makeGallerySummary(for identifier: EHGalleryIdentifier) -> CachedGallerySummary? {
        let cacheRecords = index.pages.values.filter { $0.galleryIdentifier == identifier }
        let cacheSummary = makeCacheGallerySummary(for: identifier, records: cacheRecords)
        let storedSummary = persistentGalleryStore?.summaries.first {
            $0.galleryIdentifier == identifier
        }
        return mergeGallerySummary(cacheSummary: cacheSummary, storedSummary: storedSummary)
    }

    /// Merges one permanent summary over any disposable cache pages for the same gallery.
    private func mergeGallerySummary(
        cacheSummary: CachedGallerySummary?,
        storedSummary: CachedGallerySummary?
    ) -> CachedGallerySummary? {
        guard let storedSummary else { return cacheSummary }
        guard let cacheSummary else { return storedSummary }

        var recordsByPage = Dictionary(
            uniqueKeysWithValues: cacheSummary.pageRecords.map { ($0.pageNumber, $0) }
        )
        for record in storedSummary.pageRecords {
            recordsByPage[record.pageNumber] = record
        }
        let records = recordsByPage.values.sorted { $0.pageNumber < $1.pageNumber }
        var countedCacheKeys: Set<String> = []
        let byteCount = records.reduce(Int64(0)) { total, record in
            if record.localFileURL != nil {
                return total + record.byteCount
            }
            guard countedCacheKeys.insert(record.cacheKey).inserted else { return total }
            return total + record.byteCount
        }
        return CachedGallerySummary(
            galleryIdentifier: storedSummary.galleryIdentifier,
            title: storedSummary.title,
            note: storedSummary.note ?? cacheSummary.note,
            thumbnailURL: storedSummary.thumbnailURL ?? cacheSummary.thumbnailURL,
            cachedPageCount: records.count,
            totalPageCount: storedSummary.totalPageCount ?? cacheSummary.totalPageCount,
            byteCount: byteCount,
            updatedAt: max(storedSummary.updatedAt, cacheSummary.updatedAt),
            pageRecords: records,
            isDownloadUnavailable: storedSummary.isDownloadUnavailable || cacheSummary.isDownloadUnavailable,
            isStaged: storedSummary.isStaged,
            isStagedComplete: storedSummary.isStagedComplete,
            storageState: storedSummary.storageState == .persistent ? .persistent : cacheSummary.storageState
        )
    }

    /// Resolves cache-backed source files for a permanent gallery operation.
    private func cachedPageInputs(for summary: CachedGallerySummary) -> [CachedGalleryPageInput] {
        summary.pageRecords.compactMap { record in
            guard !record.cacheKey.hasPrefix("persistent:") else { return nil }
            let sourceFileURL = fileURL(forKey: record.cacheKey)
            guard fileManager.fileExists(atPath: sourceFileURL.path) else { return nil }
            return CachedGalleryPageInput(
                pageNumber: record.pageNumber,
                pageURL: record.pageURL,
                imageURL: record.imageURL,
                thumbnailURL: record.thumbnailURL,
                sourceFileURL: sourceFileURL,
                updatedAt: record.updatedAt
            )
        }
    }

    /// Updates visible cache stats after saving one image without scanning every file.
    private func refreshAfterSaving(cacheKey: String, byteCount: Int64, context: ImageCacheContext?) {
        let previousByteCount = cacheFileSizeByKey[cacheKey]
        cacheFileSizeByKey[cacheKey] = byteCount
        let fileDelta = previousByteCount == nil ? 1 : 0
        let byteDelta = byteCount - (previousByteCount ?? 0)

        snapshot = ImageCacheSnapshot(
            fileCount: max(0, snapshot.fileCount + fileDelta),
            byteCount: max(0, snapshot.byteCount + byteDelta),
            galleryCount: gallerySummaries.count
        )

        if context?.galleryIdentifier != nil, deferredGallerySummaryRefreshDepth == 0 {
            publishGallerySummaries()
        }
    }

    /// Coalesces gallery summary refreshes while downloads save many pages quickly.
    private func scheduleGallerySummaryRefresh() {
        let elapsed = Date().timeIntervalSince(lastGallerySummaryRefreshAt)
        if elapsed >= gallerySummaryRefreshInterval {
            publishGallerySummaries()
            return
        }

        guard pendingGallerySummaryRefreshTask == nil else { return }
        let delay = max(0, gallerySummaryRefreshInterval - elapsed)
        pendingGallerySummaryRefreshTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.publishGallerySummaries()
            self?.pendingGallerySummaryRefreshTask = nil
        }
    }

    /// Publishes the latest gallery summaries and keeps the snapshot gallery count in sync.
    private func publishGallerySummaries() {
        pendingGallerySummaryRefreshTask?.cancel()
        pendingGallerySummaryRefreshTask = nil
        setGallerySummaries(makeGallerySummaries())
        lastGallerySummaryRefreshAt = Date()
        snapshot = ImageCacheSnapshot(
            fileCount: snapshot.fileCount,
            byteCount: snapshot.byteCount,
            galleryCount: gallerySummaries.count
        )
    }

    /// Replaces one published gallery summary while preserving unrelated entries.
    private func publishGallerySummary(for identifier: EHGalleryIdentifier) {
        pendingGallerySummaryRefreshTask?.cancel()
        pendingGallerySummaryRefreshTask = nil
        var summaries = gallerySummaries.filter { $0.galleryIdentifier != identifier }
        if let summary = makeGallerySummary(for: identifier) {
            summaries.append(summary)
        }
        setGallerySummaries(summaries.sorted { $0.updatedAt > $1.updatedAt })
        lastGallerySummaryRefreshAt = Date()
        snapshot = ImageCacheSnapshot(
            fileCount: snapshot.fileCount,
            byteCount: snapshot.byteCount,
            galleryCount: gallerySummaries.count
        )
    }

    /// Coalesces actor-serialized permanent gallery scans and republishes after they finish.
    private func schedulePersistentGalleryRefresh() {
        guard pendingPersistentGalleryRefreshTask == nil, let persistentGalleryStore else { return }
        pendingPersistentGalleryRefreshTask = Task { @MainActor [weak self] in
            await persistentGalleryStore.refresh()
            guard let self, !Task.isCancelled else { return }
            self.pendingPersistentGalleryRefreshTask = nil
            if self.deferredGallerySummaryRefreshDepth == 0 {
                self.publishGallerySummaries()
            }
        }
    }

    /// Updates the published array and fast lookup table together.
    private func setGallerySummaries(_ summaries: [CachedGallerySummary]) {
        gallerySummaries = summaries
        gallerySummaryByID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.galleryIdentifier.id, $0) })
    }

    /// Loads the JSON index used for aliases and gallery summaries.
    private func loadIndex() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let decoded = try? JSONDecoder().decode(ImageCacheIndex.self, from: data)
        else {
            index = ImageCacheIndex()
            return
        }
        index = decoded
    }

    /// Saves the JSON index immediately when data must be durable before the next user action.
    private func saveIndex() {
        pendingIndexSaveTask?.cancel()
        pendingIndexSaveTask = nil
        diskWriter.writeSynchronously(index, to: indexURL, directoryURL: directoryURL)
    }

    /// Saves an immutable index snapshot after cancelling any delayed save.
    private func saveIndexAsync() async {
        pendingIndexSaveTask?.cancel()
        pendingIndexSaveTask = nil
        await writeIndexSnapshotAsync()
    }

    /// Enqueues the current index immediately and awaits its ordered disk write.
    private func writeIndexSnapshotAsync() async {
        let pendingWrite = diskWriter.enqueueWrite(index, to: indexURL, directoryURL: directoryURL)
        await pendingWrite.value
    }

    /// Captures the clear generations that must still match when an async write commits.
    private func beginCacheWrite(context: ImageCacheContext?) -> ImageCacheMutationToken {
        let scopeID = context?.galleryIdentifier?.id ?? Self.nonGalleryCacheScopeID
        nextCacheWriteSequence += 1
        return ImageCacheMutationToken(
            id: UUID(),
            sequence: nextCacheWriteSequence,
            clearGeneration: cacheClearGeneration,
            scopeID: scopeID,
            scopeGeneration: cacheScopeGeneration[scopeID, default: 0]
        )
    }

    /// Releases pending-key ownership after one async save finishes or becomes stale.
    private func endCacheWrite(_ token: ImageCacheMutationToken) {
        pendingCacheWriteByID[token.id] = nil
    }

    /// Rejects a suspended save when a full-cache or matching gallery clear happened meanwhile.
    private func isCurrentCacheWrite(_ token: ImageCacheMutationToken) -> Bool {
        guard token.clearGeneration == cacheClearGeneration else { return false }
        return token.scopeGeneration == cacheScopeGeneration[token.scopeID, default: 0]
    }

    /// Advances one cache scope so older suspended writes cannot restore removed data.
    private func advanceCacheScopeGeneration(for identifier: EHGalleryIdentifier) {
        cacheScopeGeneration[identifier.id, default: 0] += 1
    }

    /// Claims one cache key in invocation order and decides whether newer bytes must replace older work.
    private func claimCacheWriteOwnership(
        _ token: ImageCacheMutationToken,
        cacheKey: String,
        dataDigest: String
    ) -> Bool? {
        if let latestSequence = latestCacheWriteSequenceByKey[cacheKey], latestSequence > token.sequence {
            return nil
        }

        let hasPendingOwner = pendingCacheWriteByID.contains { id, pendingWrite in
            id != token.id && pendingWrite.cacheKey == cacheKey
        }
        let hasDifferentCommittedDigest = contentDigestByCacheKey[cacheKey] != dataDigest
        latestCacheWriteSequenceByKey[cacheKey] = token.sequence
        pendingCacheWriteByID[token.id] = ImageCachePendingWrite(token: token, cacheKey: cacheKey)
        return hasPendingOwner || hasDifferentCommittedDigest
    }

    /// Records the newest invocation whose data transaction completed successfully.
    private func recordSuccessfulCacheWrite(_ token: ImageCacheMutationToken, cacheKey: String) {
        let latestSequence = latestSuccessfulCacheWriteSequenceByKey[cacheKey, default: 0]
        latestSuccessfulCacheWriteSequenceByKey[cacheKey] = max(latestSequence, token.sequence)
    }

    /// Returns true only while no newer data transaction succeeded for this cache key.
    private func isLatestSuccessfulCacheWrite(
        _ token: ImageCacheMutationToken,
        cacheKey: String
    ) -> Bool {
        latestSuccessfulCacheWriteSequenceByKey[cacheKey] == token.sequence
    }

    /// Rolls back a failed claim and removes any earlier stale bytes left without an owner.
    private func releaseFailedCacheWriteClaim(_ token: ImageCacheMutationToken) {
        guard let pendingWrite = pendingCacheWriteByID[token.id] else { return }
        let cacheKey = pendingWrite.cacheKey
        guard latestCacheWriteSequenceByKey[cacheKey] == token.sequence else { return }
        latestCacheWriteSequenceByKey[cacheKey] = latestSuccessfulCacheWriteSequenceByKey[cacheKey]
        removeUnreferencedCacheFileIfNeeded(
            at: fileURL(forKey: cacheKey),
            cacheKey: cacheKey,
            excluding: token.id
        )
    }

    /// Reconciles shared references with the newest bytes when their page context became stale.
    private func reconcileStaleSuccessfulCacheWrite(
        _ token: ImageCacheMutationToken,
        dataDigest: String,
        storedByteCount: Int64,
        cacheKey: String,
        fileURL: URL
    ) {
        guard isLatestSuccessfulCacheWrite(token, cacheKey: cacheKey) else {
            removeUnreferencedCacheFileIfNeeded(
                at: fileURL,
                cacheKey: cacheKey,
                excluding: token.id
            )
            return
        }

        let referencedPageKeys = index.pages.compactMap { pageKey, record in
            record.cacheKey == cacheKey ? pageKey : nil
        }
        let hasExistingAlias = index.aliases.values.contains(cacheKey)
        guard !referencedPageKeys.isEmpty || hasExistingAlias else {
            guard !hasCurrentPendingCacheWrite(cacheKey: cacheKey, excluding: token.id) else { return }
            index.aliases = index.aliases.filter { $0.value != cacheKey }
            contentDigestByCacheKey[cacheKey] = nil
            cacheKeyByContentDigest = cacheKeyByContentDigest.filter { $0.value != cacheKey }
            let removedByteCount = cacheFileSizeByKey.removeValue(forKey: cacheKey)
            diskWriter.removeFileSynchronously(fileURL)
            snapshot = ImageCacheSnapshot(
                fileCount: max(0, snapshot.fileCount - (removedByteCount == nil ? 0 : 1)),
                byteCount: max(0, snapshot.byteCount - (removedByteCount ?? 0)),
                galleryCount: gallerySummaries.count
            )
            saveIndexAfterCacheMutation()
            return
        }

        let previousByteCount = cacheFileSizeByKey[cacheKey]
        storeContentDigest(dataDigest, cacheKey: cacheKey)
        cacheFileSizeByKey[cacheKey] = storedByteCount
        for pageKey in referencedPageKeys {
            guard var record = index.pages[pageKey] else { continue }
            record.byteCount = storedByteCount
            index.pages[pageKey] = record
        }
        snapshot = ImageCacheSnapshot(
            fileCount: snapshot.fileCount + (previousByteCount == nil ? 1 : 0),
            byteCount: max(0, snapshot.byteCount - (previousByteCount ?? 0) + storedByteCount),
            galleryCount: gallerySummaries.count
        )
        saveIndexAfterCacheMutation()
        if deferredGallerySummaryRefreshDepth == 0 {
            publishGallerySummaries()
        }
    }

    /// Returns whether another valid save still owns the same cache key.
    private func hasCurrentPendingCacheWrite(cacheKey: String, excluding mutationID: UUID) -> Bool {
        pendingCacheWriteByID.contains { id, pendingWrite in
            id != mutationID
                && pendingWrite.cacheKey == cacheKey
                && isCurrentCacheWrite(pendingWrite.token)
        }
    }

    /// Removes stale bytes only when no live index entry or concurrent save still owns them.
    private func removeUnreferencedCacheFileIfNeeded(
        at fileURL: URL,
        cacheKey: String,
        excluding mutationID: UUID
    ) {
        guard !index.aliases.values.contains(cacheKey), !index.pages.values.contains(where: { $0.cacheKey == cacheKey }) else {
            return
        }
        guard !hasCurrentPendingCacheWrite(cacheKey: cacheKey, excluding: mutationID) else { return }
        diskWriter.removeFileSynchronously(fileURL)
    }

    /// Returns cache keys owned by writes that remain valid after the latest clear.
    private func currentPendingCacheKeys() -> Set<String> {
        Set(pendingCacheWriteByID.values.compactMap { pendingWrite in
            isCurrentCacheWrite(pendingWrite.token) ? pendingWrite.cacheKey : nil
        })
    }

    /// Replaces a delayed or in-flight write with the latest index snapshot.
    private func flushPendingIndexSaveAsync() async {
        guard let pendingTask = pendingIndexSaveTask else { return }
        pendingTask.cancel()
        pendingIndexSaveTask = nil
        await pendingTask.value
        await writeIndexSnapshotAsync()
    }

    /// Coalesces repeated image cache writes during bulk downloads.
    private func saveIndexAfterCacheMutation() {
        if deferredGallerySummaryRefreshDepth > 0 {
            scheduleIndexSave()
        } else {
            saveIndex()
        }
    }

    /// Schedules one delayed index write for rapid page cache mutations.
    private func scheduleIndexSave() {
        pendingIndexSaveTask?.cancel()
        pendingIndexSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.indexSaveDelayNanoseconds ?? 1_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.writeIndexSnapshotAsync()
            guard !Task.isCancelled else { return }
            self.pendingIndexSaveTask = nil
        }
    }

    /// Picks a storage key while reusing legacy files and existing aliases.
    private func cacheKeyForSave(requestedURL: URL, responseURL: URL) -> String {
        let aliasURLs = cacheAliasURLs(requestedURL: requestedURL, responseURL: responseURL)
        for aliasURL in aliasURLs {
            if let key = index.aliases[aliasURL.absoluteString] {
                return key
            }
        }
        for aliasURL in aliasURLs {
            if fileManager.fileExists(atPath: legacyFileURL(for: aliasURL).path) {
                return cacheKey(for: aliasURL)
            }
        }
        return cacheKey(for: HitomiImageURLMigration.currentURL(for: responseURL))
    }

    /// Picks an async storage key from ordered in-memory state without racing queued removals.
    private func cacheKeyForAsyncSave(
        requestedURL: URL,
        responseURL: URL,
        matchingDigest digest: String
    ) -> String {
        let aliasURLs = cacheAliasURLs(requestedURL: requestedURL, responseURL: responseURL)
        for aliasURL in aliasURLs {
            if let key = index.aliases[aliasURL.absoluteString] {
                return key
            }
        }
        if let existingCacheKey = cacheKeyByContentDigest[digest] {
            return existingCacheKey
        }
        return cacheKey(for: HitomiImageURLMigration.currentURL(for: responseURL))
    }

    /// Builds cache aliases for requested, redirected, and migrated image URLs.
    private func cacheAliasURLs(requestedURL: URL, responseURL: URL) -> [URL] {
        var urls: [URL] = []
        for url in [requestedURL, responseURL] {
            for equivalentURL in HitomiImageURLMigration.equivalentURLs(for: url) where !urls.contains(equivalentURL) {
                urls.append(equivalentURL)
            }
        }
        return urls
    }

    /// Stores multiple remote URL aliases for one cache file key.
    private func storeAliases(for urls: [URL], cacheKey: String) {
        for url in urls {
            index.aliases[url.absoluteString] = cacheKey
        }
    }

    /// Replaces both digest lookups without leaving the previous digest mapped to newer bytes.
    private func storeContentDigest(_ digest: String, cacheKey: String) {
        if let previousDigest = contentDigestByCacheKey[cacheKey],
           previousDigest != digest,
           cacheKeyByContentDigest[previousDigest] == cacheKey {
            cacheKeyByContentDigest[previousDigest] = nil
        }
        contentDigestByCacheKey[cacheKey] = digest
        cacheKeyByContentDigest[digest] = cacheKey
    }

    /// Reuses an existing cache file when another URL has already stored identical bytes.
    private func cacheKeyForExistingContent(matchingDigest digest: String) -> String? {
        guard let cacheKey = cacheKeyByContentDigest[digest] else { return nil }
        return fileManager.fileExists(atPath: fileURL(forKey: cacheKey).path) ? cacheKey : nil
    }

    /// Points aliases and page records at canonical cache files after duplicate cleanup.
    private func remapIndexCacheKeys(_ replacements: [String: String]) {
        index.aliases = index.aliases.mapValues { replacements[$0] ?? $0 }
        for pageKey in Array(index.pages.keys) {
            guard var record = index.pages[pageKey], let replacement = replacements[record.cacheKey] else { continue }
            record.cacheKey = replacement
            index.pages[pageKey] = record
        }
        for (oldKey, newKey) in replacements {
            if let digest = contentDigestByCacheKey.removeValue(forKey: oldKey) {
                contentDigestByCacheKey[newKey] = digest
                cacheKeyByContentDigest[digest] = newKey
            }
        }
    }

    /// Drops aliases and page records whose backing cache file is no longer present.
    private func removeMissingIndexEntries(validCacheKeys: Set<String>) -> Bool {
        let oldAliasCount = index.aliases.count
        let oldPageCount = index.pages.count
        index.aliases = index.aliases.filter { validCacheKeys.contains($0.value) }
        index.pages = index.pages.filter { validCacheKeys.contains($0.value.cacheKey) }
        contentDigestByCacheKey = contentDigestByCacheKey.filter { validCacheKeys.contains($0.key) }
        rebuildContentDigestLookup()
        return oldAliasCount != index.aliases.count || oldPageCount != index.pages.count
    }

    /// Rebuilds the reverse digest lookup without assuming every digest is unique.
    private func rebuildContentDigestLookup() {
        cacheKeyByContentDigest = [:]
        for (cacheKey, digest) in contentDigestByCacheKey {
            cacheKeyByContentDigest[digest] = cacheKey
        }
    }

    /// Finds cache files that are not referenced by gallery page records.
    private func nonGalleryCacheKeys() -> Set<String> {
        diskCacheKeys()
            .subtracting(Set(index.pages.values.map(\.cacheKey)))
            .subtracting(currentPendingCacheKeys())
    }

    /// Reads cache file names from disk while ignoring the JSON index.
    private func diskCacheKeys() -> Set<String> {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return Set(fileURLs.map(\.lastPathComponent).filter { $0 != indexFileName })
    }

    /// Returns the byte size for one cached image file.
    private func fileSize(forKey key: String) -> Int64? {
        let values = try? fileURL(forKey: key).resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    /// Builds a stable cache file URL for a cache key.
    private func fileURL(forKey key: String) -> URL {
        directoryURL.appending(path: key, directoryHint: .notDirectory)
    }

    /// Builds the legacy cache file URL for one remote image URL.
    private func legacyFileURL(for url: URL) -> URL {
        fileURL(forKey: cacheKey(for: url))
    }

    private var indexURL: URL {
        directoryURL.appending(path: indexFileName, directoryHint: .notDirectory)
    }

    private static let nonGalleryCacheScopeID = "__non_gallery_cache__"

    /// Builds a stable page index key.
    private func pageKey(identifier: EHGalleryIdentifier, pageNumber: Int) -> String {
        "\(identifier.id)-\(pageNumber)"
    }

    /// Hashes the full URL into a filesystem-safe cache key.
    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Calculates a content digest away from the main actor for async save paths.
    nonisolated private static func contentDigestAsync(for data: Data) async -> String {
        await Task.detached(priority: .utility) {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    /// Hashes file content so duplicate cache files count once in storage stats.
    private func contentDigest(for fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return contentDigest(for: data)
    }

    /// Hashes image bytes for duplicate cache detection.
    private func contentDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Tracks a background gallery download.
struct GalleryDownloadProgress: Equatable {
    let galleryID: String
    var title: String
    var downloadedPageCount: Int
    var totalPageCount: Int
    var isRunning: Bool
    var errorMessage: String?

    var displayText: String {
        String(format: AppCopy.galleryDownloadProgressFormat, String(downloadedPageCount), String(totalPageCount))
    }
}

/// Summarizes currently active and queued gallery downloads.
struct GalleryDownloadAggregateProgress: Equatable {
    let activeDownloadCount: Int
    let queuedDownloadCount: Int
    let downloadedPageCount: Int
    let totalPageCount: Int
    let bytesPerSecond: Int64

    var progressFraction: Double {
        guard totalPageCount > 0 else { return 0 }
        return min(1, Double(downloadedPageCount) / Double(totalPageCount))
    }

    var progressText: String {
        String(
            format: AppCopy.cacheManagementProgressFormat,
            String(downloadedPageCount),
            String(totalPageCount)
        )
    }

    var speedText: String {
        let speed = ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .file)
        return String(format: AppCopy.cacheManagementSpeedFormat, speed)
    }

    var activeDownloadText: String {
        String(format: AppCopy.cacheManagementActiveDownloadsFormat, String(activeDownloadCount))
    }

    var queuedDownloadText: String {
        String(format: AppCopy.cacheManagementQueuedDownloadsFormat, String(queuedDownloadCount))
    }
}
/// Limits complete page pipelines across all active gallery jobs.
private actor GalleryDownloadPageLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let capacity: Int
    private var availablePermits: Int
    private var waiters: [Waiter] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        availablePermits = max(1, capacity)
    }

    /// Suspends until a page pipeline permit is available.
    func acquire() async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                if availablePermits > 0 {
                    availablePermits -= 1
                    continuation.resume()
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
    }

    /// Returns one permit to the oldest pending page pipeline.
    func release() {
        if waiters.isEmpty {
            availablePermits = min(capacity, availablePermits + 1)
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume()
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

/// Carries fetched image data into the non-retryable persistence stage.
private struct DownloadedGalleryPage {
    let imagePage: EHImagePage
    let dataResponse: EHDataResponse
}

/// Downloads every reader image for a gallery into the shared cache.
@MainActor
final class GalleryDownloadManager: ObservableObject {
    static let shared = GalleryDownloadManager()

    @Published private(set) var progressByGalleryID: [String: GalleryDownloadProgress] = [:]
    @Published private(set) var aggregateProgress: GalleryDownloadAggregateProgress?

    private var latestProgressByGalleryID: [String: GalleryDownloadProgress] = [:]
    private var latestAggregateProgress: GalleryDownloadAggregateProgress?
    private var pendingProgressPublishTask: Task<Void, Never>?
    private let progressPublishDelayNanoseconds: UInt64 = 350_000_000
    private let client: any EHDataHTTPClient
    private let galleryParser: EHGalleryPageParser
    private let parser: EHImagePageParser
    private let cacheStore: ImageCacheStore
    private let hitomiDataSource: HitomiDataSource
    private let maxConcurrentDownloads: Int
    private let maxConcurrentPagesPerGallery: Int
    private let maxPageDownloadRetryCount: Int
    private let retryDelayRange: ClosedRange<Double>
    private let pageLimiter: GalleryDownloadPageLimiter
    private var runningTasks: [String: RunningGalleryDownload] = [:]
    private var queuedJobs: [String: GalleryDownloadJob] = [:]
    private var queuedJobIDs: [String] = []
    private var activeRunStartedAt: Date?
    private var activeRunDownloadedByteCount: Int64 = 0

    /// Creates a download manager with injectable dependencies.
    init(
        client: any EHDataHTTPClient = URLSessionEHHTTPClient(),
        galleryParser: EHGalleryPageParser = EHGalleryPageParser(),
        parser: EHImagePageParser = EHImagePageParser(),
        cacheStore: ImageCacheStore = .shared,
        hitomiDataSource: HitomiDataSource = HitomiDataSource(),
        maxConcurrentDownloads: Int = 5,
        maxConcurrentPagesPerGallery: Int = 3,
        maxConcurrentPageOperations: Int = 4,
        maxPageDownloadRetryCount: Int = 2,
        retryDelayRange: ClosedRange<Double> = 0.35...1.25
    ) {
        self.client = client
        self.galleryParser = galleryParser
        self.parser = parser
        self.cacheStore = cacheStore
        self.hitomiDataSource = hitomiDataSource
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.maxConcurrentPagesPerGallery = max(1, maxConcurrentPagesPerGallery)
        pageLimiter = GalleryDownloadPageLimiter(capacity: maxConcurrentPageOperations)
        self.maxPageDownloadRetryCount = max(0, maxPageDownloadRetryCount)
        self.retryDelayRange = retryDelayRange
    }

    /// Returns the latest progress for one gallery.
    func progress(for identifier: EHGalleryIdentifier) -> GalleryDownloadProgress? {
        guard let storedProgress = latestProgressByGalleryID[identifier.id] ?? progressByGalleryID[identifier.id] else {
            return cachedProgress(for: identifier)
        }

        let cachedProgress = cachedProgress(for: identifier)
        let usesLocalPageCount = storedProgress.isRunning || hasPendingOrRunningJob(for: identifier)
        let downloadedPageCount = usesLocalPageCount
            ? max(storedProgress.downloadedPageCount, cachedProgress?.downloadedPageCount ?? 0)
            : (cachedProgress?.downloadedPageCount ?? 0)
        let totalPageCount = max(storedProgress.totalPageCount, cachedProgress?.totalPageCount ?? 0)
        return GalleryDownloadProgress(
            galleryID: storedProgress.galleryID,
            title: cachedProgress?.title ?? storedProgress.title,
            downloadedPageCount: downloadedPageCount,
            totalPageCount: totalPageCount,
            isRunning: storedProgress.isRunning,
            errorMessage: storedProgress.errorMessage
        )
    }

    /// Starts a non-blocking download for all currently known gallery page links.
    func startDownload(detail: EHGalleryDetail, fallback: EHSearchResult? = nil) {
        guard !hasPendingOrRunningJob(for: detail.identifier) else { return }
        let totalPageCount = detail.pageCount ?? detail.pageLinks.count
        guard !hasCompletedDownload(for: detail.identifier, totalPageCount: totalPageCount) else { return }
        setProgress(
            GalleryDownloadProgress(
                galleryID: detail.identifier.id,
                title: detail.title,
                downloadedPageCount: cachedPageCount(for: detail.identifier),
                totalPageCount: totalPageCount,
                isRunning: true,
                errorMessage: nil
            ),
            publishesImmediately: true
        )

        enqueue(
            GalleryDownloadJob(
                identifier: detail.identifier,
                title: detail.title,
                totalPageCount: totalPageCount,
                source: .detail(detail, fallback)
            )
        )
    }

    /// Starts queued downloads for galleries with missing pages or staged finalization.
    func startUnfinishedDownloads(from summaries: [CachedGallerySummary]) {
        let unfinishedSummaries = summaries.filter(\.needsDownloadResume)

        for summary in unfinishedSummaries where !hasPendingOrRunningJob(for: summary.galleryIdentifier) {
            let totalPageCount = summary.totalPageCount ?? summary.cachedPageCount
            setProgress(
                GalleryDownloadProgress(
                    galleryID: summary.galleryIdentifier.id,
                    title: summary.title,
                    downloadedPageCount: summary.cachedPageCount,
                    totalPageCount: totalPageCount,
                    isRunning: true,
                    errorMessage: nil
                )
            )

            enqueue(
                GalleryDownloadJob(
                    identifier: summary.galleryIdentifier,
                    title: summary.title,
                    totalPageCount: totalPageCount,
                    source: .cachedSummary(summary)
                )
            )
        }

        updateAggregateProgress(publishesImmediately: true)
    }

    /// Pauses every queued or running gallery download.
    func pauseAllDownloads() {
        let affectedIDs = Set(queuedJobs.keys).union(runningTasks.keys)
        for runningDownload in runningTasks.values {
            runningDownload.task.cancel()
        }
        queuedJobs.removeAll()
        queuedJobIDs.removeAll()
        runningTasks.removeAll()

        for id in affectedIDs {
            guard let progress = latestProgressByGalleryID[id] ?? progressByGalleryID[id] else { continue }
            setProgress(
                GalleryDownloadProgress(
                    galleryID: progress.galleryID,
                    title: progress.title,
                    downloadedPageCount: progress.downloadedPageCount,
                    totalPageCount: progress.totalPageCount,
                    isRunning: false,
                    errorMessage: progress.errorMessage
                )
            )
        }

        latestAggregateProgress = nil
        activeRunStartedAt = nil
        activeRunDownloadedByteCount = 0
        publishDownloadProgress()
    }

    /// Downloads reader images one page at a time.
    private func download(
        detail: EHGalleryDetail,
        fallback: EHSearchResult?,
        executionID: UUID
    ) async {
        let totalPageCount = detail.pageCount ?? detail.pageLinks.count
        var downloadedPageNumbers = cachedPageNumbers(in: detail)
        var lastErrorMessage: String?

        do {
            try await cacheStore.preparePersistentDownload(detail: detail, fallback: fallback)
            try Task.checkCancellation()
            downloadedPageNumbers = cachedPageNumbers(in: detail)
        } catch is CancellationError {
            updateProgress(
                detail: detail,
                downloadedPageCount: downloadedPageNumbers.count,
                totalPageCount: totalPageCount,
                isRunning: false,
                errorMessage: nil,
                publishesImmediately: true,
                executionID: executionID
            )
            return
        } catch {
            updateProgress(
                detail: detail,
                downloadedPageCount: downloadedPageNumbers.count,
                totalPageCount: totalPageCount,
                isRunning: false,
                errorMessage: error.localizedDescription,
                publishesImmediately: true,
                executionID: executionID
            )
            return
        }
        updateProgress(
            detail: detail,
            downloadedPageCount: downloadedPageNumbers.count,
            totalPageCount: totalPageCount,
            isRunning: true,
            errorMessage: nil,
            publishesImmediately: true,
            executionID: executionID
        )

        let missingPageLinks = detail.pageLinks
            .sorted { $0.pageNumber < $1.pageNumber }
            .filter { !downloadedPageNumbers.contains($0.pageNumber) }

        if missingPageLinks.isEmpty {
            do {
                try Task.checkCancellation()
                try await cacheStore.finalizePersistentDownload(detail.identifier)
            } catch is CancellationError {
                updateProgress(
                    detail: detail,
                    downloadedPageCount: downloadedPageNumbers.count,
                    totalPageCount: totalPageCount,
                    isRunning: false,
                    errorMessage: nil,
                    publishesImmediately: true,
                    executionID: executionID
                )
                return
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            updateProgress(
                detail: detail,
                downloadedPageCount: downloadedPageNumbers.count,
                totalPageCount: totalPageCount,
                isRunning: false,
                errorMessage: lastErrorMessage,
                publishesImmediately: true,
                executionID: executionID
            )
            return
        }

        do {
            try await downloadMissingPages(
                missingPageLinks,
                detail: detail,
                fallback: fallback,
                totalPageCount: totalPageCount
            ) { result in
                switch result.outcome {
                case .success(let byteCount):
                    if downloadedPageNumbers.insert(result.pageNumber).inserted {
                        recordDownloadedBytes(byteCount)
                    }
                    updateProgress(
                        detail: detail,
                        downloadedPageCount: downloadedPageNumbers.count,
                        totalPageCount: totalPageCount,
                        isRunning: true,
                        errorMessage: nil,
                        executionID: executionID
                    )
                case .failure(let error):
                    if error.isHTTPNotFound {
                        await cacheStore.markGalleryDownloadUnavailable(
                            detail.identifier,
                            title: detail.title,
                            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL,
                            totalPageCount: totalPageCount
                        )
                    }
                    lastErrorMessage = String(
                        format: AppCopy.galleryDownloadPageFailedFormat,
                        String(result.pageNumber),
                        error.localizedDescription
                    )
                    updateProgress(
                        detail: detail,
                        downloadedPageCount: downloadedPageNumbers.count,
                        totalPageCount: totalPageCount,
                        isRunning: true,
                        errorMessage: lastErrorMessage,
                        executionID: executionID
                    )
                }
            }
        } catch is CancellationError {
            updateProgress(
                detail: detail,
                downloadedPageCount: downloadedPageNumbers.count,
                totalPageCount: totalPageCount,
                isRunning: false,
                errorMessage: lastErrorMessage,
                publishesImmediately: true,
                executionID: executionID
            )
            return
        } catch {
            lastErrorMessage = error.localizedDescription
            updateProgress(
                detail: detail,
                downloadedPageCount: downloadedPageNumbers.count,
                totalPageCount: totalPageCount,
                isRunning: false,
                errorMessage: lastErrorMessage,
                publishesImmediately: true,
                executionID: executionID
            )
            return
        }

        if lastErrorMessage == nil,
           containsEveryExpectedPage(downloadedPageNumbers, totalPageCount: totalPageCount) {
            do {
                try Task.checkCancellation()
                try await cacheStore.finalizePersistentDownload(detail.identifier)
            } catch is CancellationError {
                updateProgress(
                    detail: detail,
                    downloadedPageCount: downloadedPageNumbers.count,
                    totalPageCount: totalPageCount,
                    isRunning: false,
                    errorMessage: nil,
                    publishesImmediately: true,
                    executionID: executionID
                )
                return
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        updateProgress(
            detail: detail,
            downloadedPageCount: downloadedPageNumbers.count,
            totalPageCount: totalPageCount,
            isRunning: false,
            errorMessage: lastErrorMessage,
            publishesImmediately: true,
            executionID: executionID
        )
    }

    /// Updates observable progress for a gallery.
    private func updateProgress(
        detail: EHGalleryDetail,
        downloadedPageCount: Int,
        totalPageCount: Int,
        isRunning: Bool,
        errorMessage: String?,
        publishesImmediately: Bool = false,
        executionID: UUID
    ) {
        guard runningTasks[detail.identifier.id]?.executionID == executionID else { return }
        setProgress(
            GalleryDownloadProgress(
                galleryID: detail.identifier.id,
                title: detail.title,
                downloadedPageCount: downloadedPageCount,
                totalPageCount: totalPageCount,
                isRunning: isRunning,
                errorMessage: errorMessage
            ),
            publishesImmediately: publishesImmediately
        )
    }

    /// Stores fresh progress and publishes it with optional throttling.
    private func setProgress(_ progress: GalleryDownloadProgress, publishesImmediately: Bool = false) {
        latestProgressByGalleryID[progress.galleryID] = progress
        updateAggregateProgress(publishesImmediately: publishesImmediately)
    }

    /// Schedules a coalesced SwiftUI progress update for rapid page completions.
    private func scheduleProgressPublish() {
        guard pendingProgressPublishTask == nil else { return }
        pendingProgressPublishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.progressPublishDelayNanoseconds ?? 350_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingProgressPublishTask = nil
            self.publishDownloadProgressNow()
        }
    }

    /// Publishes the latest download progress immediately.
    private func publishDownloadProgress() {
        pendingProgressPublishTask?.cancel()
        pendingProgressPublishTask = nil
        publishDownloadProgressNow()
    }

    /// Assigns published progress properties without touching pending timers.
    private func publishDownloadProgressNow() {
        recalculateAggregateProgress()
        progressByGalleryID = latestProgressByGalleryID
        aggregateProgress = latestAggregateProgress
    }

    /// Builds progress from cache when no download is running.
    private func cachedProgress(for identifier: EHGalleryIdentifier) -> GalleryDownloadProgress? {
        guard let summary = cacheStore.gallerySummary(for: identifier) else { return nil }
        return GalleryDownloadProgress(
            galleryID: identifier.id,
            title: summary.title,
            downloadedPageCount: summary.cachedPageCount,
            totalPageCount: summary.totalPageCount ?? summary.cachedPageCount,
            isRunning: false,
            errorMessage: nil
        )
    }

    /// Counts cached pages for one gallery.
    private func cachedPageCount(for identifier: EHGalleryIdentifier) -> Int {
        cacheStore.gallerySummary(for: identifier)?.cachedPageCount ?? 0
    }


    /// Reads available page numbers from direct cache lookups instead of throttled summaries.
    private func cachedPageNumbers(in detail: EHGalleryDetail) -> Set<Int> {
        Set(detail.pageLinks.compactMap { pageLink in
            guard
                let record = cacheStore.pageRecord(
                    for: detail.identifier,
                    pageNumber: pageLink.pageNumber
                ),
                cacheStore.containsData(for: record.imageURL)
            else {
                return nil
            }
            return pageLink.pageNumber
        })
    }

    /// Returns whether every page number from one through the total is available.
    private func containsEveryExpectedPage(
        _ pageNumbers: Set<Int>,
        totalPageCount: Int
    ) -> Bool {
        guard totalPageCount > 0 else { return false }
        return Set(1...totalPageCount).isSubset(of: pageNumbers)
    }

    /// Returns true when a gallery is already queued or actively downloading.
    private func hasPendingOrRunningJob(for identifier: EHGalleryIdentifier) -> Bool {
        runningTasks[identifier.id] != nil || queuedJobs[identifier.id] != nil
    }

    /// Returns true only when every expected page is already in finalized durable storage.
    private func hasCompletedDownload(
        for identifier: EHGalleryIdentifier,
        totalPageCount: Int
    ) -> Bool {
        guard
            totalPageCount > 0,
            let summary = cacheStore.gallerySummary(for: identifier),
            summary.storageState == .persistent,
            !summary.isStaged
        else {
            return false
        }
        let persistentPageNumbers: Set<Int> = Set(summary.pageRecords.compactMap { record -> Int? in
            guard
                let localFileURL = record.localFileURL,
                FileManager.default.fileExists(atPath: localFileURL.path)
            else {
                return nil
            }
            return record.pageNumber
        })
        return containsEveryExpectedPage(
            persistentPageNumbers,
            totalPageCount: totalPageCount
        )
    }

    /// Adds one gallery job to the queue and starts work when capacity is available.
    private func enqueue(_ job: GalleryDownloadJob) {
        guard queuedJobs[job.identifier.id] == nil, runningTasks[job.identifier.id] == nil else { return }
        queuedJobs[job.identifier.id] = job
        queuedJobIDs.append(job.identifier.id)
        scheduleDownloads()
    }

    /// Starts queued gallery jobs up to the configured concurrency limit.
    private func scheduleDownloads() {
        while runningTasks.count < maxConcurrentDownloads, let nextID = queuedJobIDs.first {
            queuedJobIDs.removeFirst()
            guard let job = queuedJobs.removeValue(forKey: nextID) else { continue }
            let executionID = UUID()
            let task = Task { [weak self] in
                guard let self else { return }
                await self.run(job, executionID: executionID)
            }
            runningTasks[nextID] = RunningGalleryDownload(executionID: executionID, task: task)
        }
        updateAggregateProgress()
    }

    /// Runs one queued job and schedules the next job after it finishes.
    private func run(_ job: GalleryDownloadJob, executionID: UUID) async {
        cacheStore.beginDeferredGallerySummaryRefreshes()
        defer {
            if runningTasks[job.identifier.id]?.executionID == executionID {
                runningTasks[job.identifier.id] = nil
                scheduleDownloads()
            }
        }

        do {
            if try await finalizeCompleteStagingIfNeeded(job, executionID: executionID) {
                setProgress(
                    GalleryDownloadProgress(
                        galleryID: job.identifier.id,
                        title: job.title,
                        downloadedPageCount: job.totalPageCount,
                        totalPageCount: job.totalPageCount,
                        isRunning: false,
                        errorMessage: nil
                    ),
                    publishesImmediately: true
                )
            } else {
                let (detail, fallback) = try await resolvedDetailAndFallback(for: job)
                try Task.checkCancellation()
                guard runningTasks[job.identifier.id]?.executionID == executionID else {
                    throw CancellationError()
                }
                await cacheStore.saveGalleryMetadataForDownload(detail: detail, fallback: fallback)
                try Task.checkCancellation()
                guard runningTasks[job.identifier.id]?.executionID == executionID else {
                    throw CancellationError()
                }
                await download(detail: detail, fallback: fallback, executionID: executionID)
            }
        } catch is CancellationError {
            markJobPaused(job, executionID: executionID)
        } catch {
            if runningTasks[job.identifier.id]?.executionID == executionID {
                if error.isHTTPNotFound {
                    await cacheStore.markGalleryDownloadUnavailable(
                        job.identifier,
                        title: job.title,
                        totalPageCount: job.totalPageCount
                    )
                }
                let downloadedPageCount = cachedPageCount(for: job.identifier)
                setProgress(
                    GalleryDownloadProgress(
                        galleryID: job.identifier.id,
                        title: job.title,
                        downloadedPageCount: downloadedPageCount,
                        totalPageCount: job.totalPageCount,
                        isRunning: false,
                        errorMessage: error.localizedDescription
                    ),
                    publishesImmediately: true
                )
            }
        }
        await cacheStore.endDeferredGallerySummaryRefreshes(for: job.identifier)
    }

    /// Finalizes a complete staged bulk job without requiring remote gallery metadata.
    private func finalizeCompleteStagingIfNeeded(
        _ job: GalleryDownloadJob,
        executionID: UUID
    ) async throws -> Bool {
        guard case .cachedSummary = job.source,
              cacheStore.hasCompletePersistentStaging(for: job.identifier)
        else {
            return false
        }
        try Task.checkCancellation()
        guard runningTasks[job.identifier.id]?.executionID == executionID else {
            throw CancellationError()
        }
        try await cacheStore.finalizePersistentDownload(job.identifier)
        try Task.checkCancellation()
        guard runningTasks[job.identifier.id]?.executionID == executionID else {
            throw CancellationError()
        }
        return true
    }

    /// Marks a cancelled job as paused instead of failed.
    private func markJobPaused(_ job: GalleryDownloadJob, executionID: UUID) {
        guard runningTasks[job.identifier.id]?.executionID == executionID else { return }
        let progress = latestProgressByGalleryID[job.identifier.id] ?? progressByGalleryID[job.identifier.id]
        setProgress(
            GalleryDownloadProgress(
                galleryID: job.identifier.id,
                title: progress?.title ?? job.title,
                downloadedPageCount: progress?.downloadedPageCount ?? cachedPageCount(for: job.identifier),
                totalPageCount: progress?.totalPageCount ?? job.totalPageCount,
                isRunning: false,
                errorMessage: progress?.errorMessage
            ),
            publishesImmediately: true
        )
    }

    /// Resolves full gallery page links for a queued job.
    private func resolvedDetailAndFallback(for job: GalleryDownloadJob) async throws -> (EHGalleryDetail, EHSearchResult?) {
        switch job.source {
        case .detail(let detail, let fallback):
            return (detail, fallback)
        case .cachedSummary(let summary):
            let detail = try await loadCompleteDetail(for: summary)
            return (detail, summary.searchResult)
        }
    }

    /// Loads the gallery detail page and every known thumbnail page for a cached summary.
    private func loadCompleteDetail(for summary: CachedGallerySummary) async throws -> EHGalleryDetail {
        if summary.galleryIdentifier.site == .hitomi {
            var detail = try await hitomiDataSource.galleryDetail(from: summary.galleryIdentifier.url())
            while detail.pageLinks.count < (detail.pageCount ?? detail.pageLinks.count) {
                let incomingPageLinks = try await hitomiDataSource.galleryPageLinks(
                    from: summary.galleryIdentifier.url(),
                    startPage: detail.pageLinks.count + 1
                )
                guard !incomingPageLinks.isEmpty else { break }
                detail = mergedDetail(detail, appending: incomingPageLinks)
            }
            return detail
        }

        let response = try await client.get(summary.galleryIdentifier.url())
        var detail = try galleryParser.parse(response.body, sourceURL: response.url)
        var loadedThumbnailPageURLStrings: Set<String> = [response.url.absoluteString]

        while let nextURL = detail.thumbnailPageURLs.first(where: { !loadedThumbnailPageURLStrings.contains($0.absoluteString) }) {
            let pageResponse = try await client.get(nextURL)
            let incomingDetail = try galleryParser.parse(pageResponse.body, sourceURL: pageResponse.url)
            loadedThumbnailPageURLStrings.insert(pageResponse.url.absoluteString)
            detail = mergedDetail(detail, with: incomingDetail)
        }

        return detail
    }

    /// Combines Hitomi page links while keeping gallery-level metadata.
    private func mergedDetail(_ current: EHGalleryDetail, appending incomingPageLinks: [EHGalleryPageLink]) -> EHGalleryDetail {
        let pageLinks = Dictionary(grouping: current.pageLinks + incomingPageLinks, by: \.pageNumber)
            .compactMap { $0.value.first }
            .sorted { $0.pageNumber < $1.pageNumber }

        return EHGalleryDetail(
            identifier: current.identifier,
            title: current.title,
            japaneseTitle: current.japaneseTitle,
            category: current.category,
            coverURL: current.coverURL,
            uploader: current.uploader,
            metadata: current.metadata,
            ratingLabel: current.ratingLabel,
            ratingCount: current.ratingCount,
            tags: current.tags,
            pageLinks: pageLinks,
            thumbnailPageURLs: current.thumbnailPageURLs,
            pageCount: current.pageCount,
            relatedGalleries: current.relatedGalleries
        )
    }

    /// Combines thumbnail page links while keeping the first page's gallery metadata.
    private func mergedDetail(_ current: EHGalleryDetail, with incoming: EHGalleryDetail) -> EHGalleryDetail {
        let pageLinks = Dictionary(grouping: current.pageLinks + incoming.pageLinks, by: \.pageNumber)
            .compactMap { $0.value.first }
            .sorted { $0.pageNumber < $1.pageNumber }
        let thumbnailPageURLs = Array(Set(current.thumbnailPageURLs + incoming.thumbnailPageURLs))
            .sorted { $0.absoluteString < $1.absoluteString }

        return EHGalleryDetail(
            identifier: current.identifier,
            title: current.title,
            japaneseTitle: current.japaneseTitle,
            category: current.category,
            coverURL: current.coverURL,
            uploader: current.uploader,
            metadata: current.metadata,
            ratingLabel: current.ratingLabel,
            ratingCount: current.ratingCount,
            tags: current.tags,
            pageLinks: pageLinks,
            thumbnailPageURLs: thumbnailPageURLs,
            pageCount: current.pageCount ?? incoming.pageCount,
            relatedGalleries: current.relatedGalleries.isEmpty ? incoming.relatedGalleries : current.relatedGalleries
        )
    }

    /// Downloads missing pages with a small per-gallery concurrency window.
    private func downloadMissingPages(
        _ pageLinks: [EHGalleryPageLink],
        detail: EHGalleryDetail,
        fallback: EHSearchResult?,
        totalPageCount: Int,
        onResult: @MainActor (GalleryPageDownloadResult) async -> Void
    ) async throws {
        var nextPageIndex = 0

        try await withThrowingTaskGroup(of: GalleryPageDownloadResult.self) { group in
            /// Starts one page task when there is capacity and pending work.
            func enqueueNextPageIfNeeded() {
                guard nextPageIndex < pageLinks.count else { return }
                let pageLink = pageLinks[nextPageIndex]
                nextPageIndex += 1
                group.addTask {
                    await self.downloadPageResult(
                        pageLink,
                        detail: detail,
                        fallback: fallback,
                        totalPageCount: totalPageCount
                    )
                }
            }

            for _ in 0..<min(maxConcurrentPagesPerGallery, pageLinks.count) {
                enqueueNextPageIfNeeded()
            }

            while let result = try await group.next() {
                try Task.checkCancellation()
                await onResult(result)
                enqueueNextPageIfNeeded()
            }
        }
    }

    /// Converts one page download attempt into a non-cancelling result.
    private func downloadPageResult(
        _ pageLink: EHGalleryPageLink,
        detail: EHGalleryDetail,
        fallback: EHSearchResult?,
        totalPageCount: Int
    ) async -> GalleryPageDownloadResult {
        do {
            try await pageLimiter.acquire()
            do {
                try Task.checkCancellation()
                let byteCount = try await downloadPage(
                    pageLink,
                    detail: detail,
                    fallback: fallback,
                    totalPageCount: totalPageCount
                )
                await pageLimiter.release()
                return GalleryPageDownloadResult(pageNumber: pageLink.pageNumber, outcome: .success(byteCount))
            } catch {
                await pageLimiter.release()
                throw error
            }
        } catch {
            return GalleryPageDownloadResult(pageNumber: pageLink.pageNumber, outcome: .failure(error))
        }
    }

    /// Retries the network stage, then persists successful bytes exactly once.
    private func downloadPage(
        _ pageLink: EHGalleryPageLink,
        detail: EHGalleryDetail,
        fallback: EHSearchResult?,
        totalPageCount: Int
    ) async throws -> Int64 {
        var downloadedPage: DownloadedGalleryPage?
        var lastError: Error?

        for attempt in 0...maxPageDownloadRetryCount {
            do {
                try Task.checkCancellation()
                downloadedPage = try await fetchPageOnce(pageLink, detail: detail)
                break
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard
                    attempt < maxPageDownloadRetryCount,
                    shouldRetryPageFetch(after: error)
                else {
                    break
                }
                try await waitBeforeRetry()
            }
        }

        guard let downloadedPage else {
            throw lastError ?? EHNetworkError.invalidResponse
        }

        let context = ImageCacheContext(
            galleryIdentifier: detail.identifier,
            galleryTitle: detail.title,
            pageNumber: downloadedPage.imagePage.pageNumber,
            pageURL: downloadedPage.imagePage.pageURL,
            totalPageCount: totalPageCount,
            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL
        )
        try Task.checkCancellation()
        try await cacheStore.saveDownloadedPageAsync(
            downloadedPage.dataResponse.data,
            for: downloadedPage.imagePage.imageURL,
            responseURL: downloadedPage.dataResponse.url,
            context: context
        )
        return Int64(downloadedPage.dataResponse.data.count)
    }

    /// Performs a single reader page and image download attempt.
    private func fetchPageOnce(
        _ pageLink: EHGalleryPageLink,
        detail: EHGalleryDetail
    ) async throws -> DownloadedGalleryPage {
        try Task.checkCancellation()
        let imagePage: EHImagePage
        if detail.identifier.site == .hitomi {
            imagePage = try await hitomiDataSource.imagePage(from: pageLink.pageURL)
        } else {
            let pageResponse = try await client.get(pageLink.pageURL)
            try Task.checkCancellation()
            imagePage = try parser.parse(pageResponse.body, sourceURL: pageResponse.url)
        }
        let imageReferer = detail.identifier.site == .hitomi
            ? (imagePage.galleryURL ?? imagePage.pageURL)
            : imagePage.pageURL
        let dataResponse = try await client.data(imagePage.imageURL, referer: imageReferer)
        try Task.checkCancellation()
        return DownloadedGalleryPage(imagePage: imagePage, dataResponse: dataResponse)
    }

    /// Waits for a short randomized retry delay to avoid hammering the image host.
    private func waitBeforeRetry() async throws {
        let delay = Double.random(in: retryDelayRange)
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        guard nanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }


    /// Retries only transport and server failures that can succeed without changing input.
    private func shouldRetryPageFetch(after error: Error) -> Bool {
        if error.isHTTPNotFound || error is CancellationError {
            return false
        }
        if let networkError = error as? EHNetworkError {
            switch networkError {
            case .invalidResponse:
                return true
            case .unacceptableStatusCode(let statusCode):
                return statusCode == 408
                    || statusCode == 425
                    || statusCode == 429
                    || (500...599).contains(statusCode)
            case .undecodableBody:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .resourceUnavailable,
                 .notConnectedToInternet,
                 .secureConnectionFailed,
                 .cannotLoadFromNetwork,
                 .backgroundSessionWasDisconnected:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Records bytes downloaded during the current active run.
    private func recordDownloadedBytes(_ byteCount: Int64) {
        if activeRunStartedAt == nil {
            activeRunStartedAt = Date()
        }
        activeRunDownloadedByteCount += byteCount
    }

    /// Publishes aggregate progress while at least one gallery download is active.
    private func updateAggregateProgress(publishesImmediately: Bool = false) {
        if publishesImmediately {
            publishDownloadProgress()
        } else {
            scheduleProgressPublish()
        }
    }


    /// Rebuilds aggregate values only when observable progress is published.
    private func recalculateAggregateProgress() {
        let activeDownloadCount = runningTasks.count
        guard activeDownloadCount > 0 else {
            latestAggregateProgress = nil
            activeRunStartedAt = nil
            activeRunDownloadedByteCount = 0
            return
        }

        if activeRunStartedAt == nil {
            activeRunStartedAt = Date()
            activeRunDownloadedByteCount = 0
        }

        let runningProgresses = latestProgressByGalleryID.values.filter { $0.isRunning }
        let downloadedPageCount = runningProgresses.reduce(0) { $0 + $1.downloadedPageCount }
        let totalPageCount = runningProgresses.reduce(0) { $0 + $1.totalPageCount }
        let elapsed = max(Date().timeIntervalSince(activeRunStartedAt ?? Date()), 0.1)
        let bytesPerSecond = Int64(Double(activeRunDownloadedByteCount) / elapsed)

        latestAggregateProgress = GalleryDownloadAggregateProgress(
            activeDownloadCount: activeDownloadCount,
            queuedDownloadCount: queuedJobs.count,
            downloadedPageCount: downloadedPageCount,
            totalPageCount: totalPageCount,
            bytesPerSecond: bytesPerSecond
        )
    }
}

/// Stores the result for one downloaded gallery page.
private struct GalleryPageDownloadResult {
    let pageNumber: Int
    let outcome: Result<Int64, Error>
}

/// Stores a queued gallery download request.
private struct GalleryDownloadJob {
    let identifier: EHGalleryIdentifier
    let title: String
    let totalPageCount: Int
    let source: GalleryDownloadJobSource
}

/// Associates one tracked task with the execution that owns its gallery slot.
private struct RunningGalleryDownload {
    let executionID: UUID
    let task: Task<Void, Never>
}

/// Describes how a queued download should resolve its page links.
private enum GalleryDownloadJobSource {
    case detail(EHGalleryDetail, EHSearchResult?)
    case cachedSummary(CachedGallerySummary)
}

/// Stores cache aliases and reader page mappings.
private struct ImageCacheIndex: Codable, Sendable {
    var aliases: [String: String] = [:]
    var pages: [String: CachedImagePageRecord] = [:]
    var galleryMetadata: [String: CachedGalleryMetadata] = [:]
}

/// Carries one immutable cache-directory scan back to the main-actor projection.
private struct ImageCacheDirectorySnapshot: Sendable {
    let fileSizeByKey: [String: Int64]
    let byteCount: Int64
}

/// Describes one incremental disposable-cache removal.
private struct ImageCacheGalleryRemoval {
    let removableCacheKeys: Set<String>
    let didChange: Bool
}

/// Identifies one async cache save across suspension points and user clears.
private struct ImageCacheMutationToken {
    let id: UUID
    let sequence: UInt64
    let clearGeneration: Int
    let scopeID: String
    let scopeGeneration: Int
}

/// Associates one in-flight save token with the cache key it currently owns.
private struct ImageCachePendingWrite {
    let token: ImageCacheMutationToken
    let cacheKey: String
}

/// Serializes cache file removals and immutable index snapshots outside MainActor.
private final class ImageCacheDiskWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ikode.MyEHViewer.image-cache-writer", qos: .utility)
    private let beforeMutation: @Sendable () -> Void
    private let beforeDataWrite: @Sendable () throws -> Void

    /// Creates one FIFO writer with an optional deterministic test boundary.
    init(
        beforeMutation: @escaping @Sendable () -> Void = {},
        beforeDataWrite: @escaping @Sendable () throws -> Void = {}
    ) {
        self.beforeMutation = beforeMutation
        self.beforeDataWrite = beforeDataWrite
    }

    /// Preserves immediate cleanup semantics for explicit user commands.
    func writeSynchronously(
        _ index: ImageCacheIndex,
        to indexURL: URL,
        directoryURL: URL,
        removing fileURLs: [URL] = []
    ) {
        queue.sync {
            beforeMutation()
            Self.write(index, to: indexURL, directoryURL: directoryURL, removing: fileURLs)
        }
    }

    /// Enqueues a download-driven mutation immediately and returns a durability task.
    func enqueueWrite(
        _ index: ImageCacheIndex,
        to indexURL: URL,
        directoryURL: URL,
        removing fileURLs: [URL] = []
    ) -> Task<Void, Never> {
        let completion = ImageCacheWriteCompletion()
        queue.async {
            self.beforeMutation()
            Self.write(index, to: indexURL, directoryURL: directoryURL, removing: fileURLs)
            completion.finish()
        }
        return Task {
            await withCheckedContinuation { continuation in
                completion.whenFinished(continuation)
            }
        }
    }

    /// Checks file existence and conditionally writes bytes in one FIFO transaction.
    func enqueueDataWrite(
        _ data: Data,
        to destinationURL: URL,
        replacesExisting: Bool
    ) -> Task<Int64, Error> {
        let completion = ImageCacheDataWriteCompletion()
        queue.async {
            self.beforeMutation()
            do {
                try self.beforeDataWrite()
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if replacesExisting || !FileManager.default.fileExists(atPath: destinationURL.path) {
                    try data.write(to: destinationURL, options: [.atomic])
                }
                let values = try? destinationURL.resourceValues(forKeys: [.fileSizeKey])
                let byteCount = Int64(values?.fileSize ?? data.count)
                completion.finish(.success(byteCount))
            } catch {
                completion.finish(.failure(error))
            }
        }
        return Task {
            let result = await withCheckedContinuation { continuation in
                completion.whenFinished(continuation)
            }
            return try result.get()
        }
    }

    /// Performs one ordered data transaction for synchronous cache callers.
    func writeDataSynchronously(
        _ data: Data,
        to destinationURL: URL,
        replacesExisting: Bool
    ) throws -> Int64 {
        try queue.sync {
            beforeMutation()
            try beforeDataWrite()
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if replacesExisting || !FileManager.default.fileExists(atPath: destinationURL.path) {
                try data.write(to: destinationURL, options: [.atomic])
            }
            let values = try? destinationURL.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? data.count)
        }
    }

    /// Removes the whole cache directory after every earlier queued mutation finishes.
    func removeDirectorySynchronously(_ directoryURL: URL) {
        queue.sync {
            beforeMutation()
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    /// Removes one cache file after every earlier FIFO mutation finishes.
    func removeFileSynchronously(_ fileURL: URL) {
        queue.sync {
            beforeMutation()
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Applies file removals before atomically replacing the index snapshot.
    private static func write(
        _ index: ImageCacheIndex,
        to indexURL: URL,
        directoryURL: URL,
        removing fileURLs: [URL]
    ) {
        do {
            for fileURL in fileURLs {
                try? FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save image cache index: \(error.localizedDescription)")
        }
    }
}

/// Bridges one serial queue write back into async code without delaying its enqueue.
private final class ImageCacheWriteCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    /// Resumes immediately when work is done or stores the waiter for later completion.
    func whenFinished(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.resume()
            return
        }
        continuations.append(continuation)
        lock.unlock()
    }

    /// Completes every registered waiter after the serial disk operation exits.
    func finish() {
        lock.lock()
        isFinished = true
        let pendingContinuations = continuations
        continuations.removeAll()
        lock.unlock()
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}

/// Bridges a fallible serial image write back into async cache code.
private final class ImageCacheDataWriteCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Int64, Error>?
    private var continuations: [CheckedContinuation<Result<Int64, Error>, Never>] = []

    /// Resumes immediately when work is done or stores the waiter for later completion.
    func whenFinished(_ continuation: CheckedContinuation<Result<Int64, Error>, Never>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
            return
        }
        continuations.append(continuation)
        lock.unlock()
    }

    /// Completes every registered waiter with the data write result.
    func finish(_ result: Result<Int64, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let pendingContinuations = continuations
        continuations.removeAll()
        lock.unlock()
        for continuation in pendingContinuations {
            continuation.resume(returning: result)
        }
    }
}

/// Stores gallery-level metadata for partially indexed caches.
private struct CachedGalleryMetadata: Codable, Hashable, Sendable {
    let identifier: EHGalleryIdentifier
    let title: String
    let note: String?
    let thumbnailURL: URL?
    let totalPageCount: Int?
    let updatedAt: Date
    let isDownloadUnavailable: Bool

    /// Creates metadata and defaults the download marker to available.
    init(
        identifier: EHGalleryIdentifier,
        title: String,
        note: String? = nil,
        thumbnailURL: URL?,
        totalPageCount: Int?,
        updatedAt: Date,
        isDownloadUnavailable: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.note = note
        self.thumbnailURL = thumbnailURL
        self.totalPageCount = totalPageCount
        self.updatedAt = updatedAt
        self.isDownloadUnavailable = isDownloadUnavailable
    }

    /// Decodes older cache indexes that do not contain the 404 marker.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(EHGalleryIdentifier.self, forKey: .identifier)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        totalPageCount = try container.decodeIfPresent(Int.self, forKey: .totalPageCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isDownloadUnavailable = try container.decodeIfPresent(Bool.self, forKey: .isDownloadUnavailable) ?? false
    }
}
