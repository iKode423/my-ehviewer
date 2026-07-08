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
        let (data, httpResponse) = try await responseData(for: makeRequest(
            url,
            accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            referer: referer ?? EHConstants.baseURL
        ))
        return EHDataResponse(url: httpResponse.url ?? url, statusCode: httpResponse.statusCode, data: data)
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
struct CachedImagePageRecord: Codable, Hashable, Identifiable {
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

    var id: String { "\(galleryIdentifier.id)-\(pageNumber)" }
}

/// Summarizes cached pages for one gallery.
struct CachedGallerySummary: Hashable, Identifiable {
    let galleryIdentifier: EHGalleryIdentifier
    let title: String
    let thumbnailURL: URL?
    let cachedPageCount: Int
    let totalPageCount: Int?
    let byteCount: Int64
    let updatedAt: Date
    let pageRecords: [CachedImagePageRecord]
    let isDownloadUnavailable: Bool

    /// Creates a cache summary while keeping the 404 marker optional for older call sites.
    init(
        galleryIdentifier: EHGalleryIdentifier,
        title: String,
        thumbnailURL: URL?,
        cachedPageCount: Int,
        totalPageCount: Int?,
        byteCount: Int64,
        updatedAt: Date,
        pageRecords: [CachedImagePageRecord],
        isDownloadUnavailable: Bool = false
    ) {
        self.galleryIdentifier = galleryIdentifier
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.cachedPageCount = cachedPageCount
        self.totalPageCount = totalPageCount
        self.byteCount = byteCount
        self.updatedAt = updatedAt
        self.pageRecords = pageRecords
        self.isDownloadUnavailable = isDownloadUnavailable
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
    static let shared = ImageCacheStore()

    @Published private(set) var snapshot: ImageCacheSnapshot = .empty
    @Published private(set) var gallerySummaries: [CachedGallerySummary] = []

    private let directoryURL: URL
    private let fileManager: FileManager
    private let indexFileName = "index.json"
    private var index = ImageCacheIndex()
    private var contentDigestByCacheKey: [String: String] = [:]
    private var cacheKeyByContentDigest: [String: String] = [:]
    private var cacheFileSizeByKey: [String: Int64] = [:]

    /// Creates a cache store rooted in the app caches directory by default.
    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
            self.directoryURL = baseURL.appending(path: "ImageCache", directoryHint: .isDirectory)
        }
        loadIndex()
        refresh(compactsDuplicates: false)
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
        if let cacheKey = index.aliases[url.absoluteString] {
            let fileURL = fileURL(forKey: cacheKey)
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        let legacyURL = legacyFileURL(for: url)
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return nil
    }

    /// Returns a cached reader page for a specific reader URL.
    func pageRecord(for pageURL: URL) -> CachedImagePageRecord? {
        index.pages.values.first { $0.pageURL == pageURL }
    }

    /// Returns a cached reader page for a gallery page number.
    func pageRecord(for identifier: EHGalleryIdentifier, pageNumber: Int) -> CachedImagePageRecord? {
        index.pages[pageKey(identifier: identifier, pageNumber: pageNumber)]
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

    /// Stores gallery metadata so cache management can list partially downloaded galleries.
    func saveGalleryMetadata(detail: EHGalleryDetail, fallback: EHSearchResult? = nil) {
        index.galleryMetadata[detail.identifier.id] = CachedGalleryMetadata(
            identifier: detail.identifier,
            title: detail.title,
            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL,
            totalPageCount: detail.pageCount,
            updatedAt: Date(),
            isDownloadUnavailable: false
        )
        saveIndex()
        refresh(compactsDuplicates: false)
    }

    /// Marks a cached gallery as unavailable for future bulk download resumes.
    func markGalleryDownloadUnavailable(
        _ identifier: EHGalleryIdentifier,
        title: String? = nil,
        thumbnailURL: URL? = nil,
        totalPageCount: Int? = nil
    ) {
        let existing = index.galleryMetadata[identifier.id]
        index.galleryMetadata[identifier.id] = CachedGalleryMetadata(
            identifier: identifier,
            title: title ?? existing?.title ?? "图库 \(identifier.gid)",
            thumbnailURL: thumbnailURL ?? existing?.thumbnailURL,
            totalPageCount: totalPageCount ?? existing?.totalPageCount,
            updatedAt: Date(),
            isDownloadUnavailable: true
        )
        saveIndex()
        refresh(compactsDuplicates: false)
    }

    /// Saves image data and refreshes cache usage stats.
    func save(_ data: Data, for url: URL) {
        save(data, for: url, responseURL: url, context: nil)
    }

    /// Saves image data with aliases and optional gallery page metadata.
    func save(_ data: Data, for requestedURL: URL, responseURL: URL, context: ImageCacheContext?) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let dataDigest = contentDigest(for: data)
            var cacheKey = cacheKeyForSave(requestedURL: requestedURL, responseURL: responseURL)
            var destinationURL = fileURL(forKey: cacheKey)
            if !fileManager.fileExists(atPath: destinationURL.path),
               let existingCacheKey = cacheKeyForExistingContent(matchingDigest: dataDigest) {
                cacheKey = existingCacheKey
                destinationURL = fileURL(forKey: existingCacheKey)
            }
            if !fileManager.fileExists(atPath: destinationURL.path) {
                try data.write(to: destinationURL, options: [.atomic])
            }
            let storedByteCount = fileSize(forKey: cacheKey) ?? Int64(data.count)

            contentDigestByCacheKey[cacheKey] = dataDigest
            cacheKeyByContentDigest[dataDigest] = cacheKey
            index.aliases[requestedURL.absoluteString] = cacheKey
            index.aliases[responseURL.absoluteString] = cacheKey
            upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: storedByteCount)
            saveIndex()
            refreshAfterSaving(cacheKey: cacheKey, byteCount: storedByteCount, context: context)
        } catch {
            assertionFailure("Failed to save image cache: \(error.localizedDescription)")
        }
    }

    /// Saves image data while moving disk writes off the main actor for async callers.
    func saveAsync(_ data: Data, for requestedURL: URL, responseURL: URL, context: ImageCacheContext?) async {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let dataDigest = await Self.contentDigestAsync(for: data)
            var cacheKey = cacheKeyForSave(requestedURL: requestedURL, responseURL: responseURL)
            var destinationURL = fileURL(forKey: cacheKey)
            if !fileManager.fileExists(atPath: destinationURL.path),
               let existingCacheKey = cacheKeyForExistingContent(matchingDigest: dataDigest) {
                cacheKey = existingCacheKey
                destinationURL = fileURL(forKey: existingCacheKey)
            }
            if !fileManager.fileExists(atPath: destinationURL.path) {
                try await Self.writeData(data, to: destinationURL)
            }
            let storedByteCount = fileSize(forKey: cacheKey) ?? Int64(data.count)

            contentDigestByCacheKey[cacheKey] = dataDigest
            cacheKeyByContentDigest[dataDigest] = cacheKey
            index.aliases[requestedURL.absoluteString] = cacheKey
            index.aliases[responseURL.absoluteString] = cacheKey
            upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: storedByteCount)
            saveIndex()
            refreshAfterSaving(cacheKey: cacheKey, byteCount: storedByteCount, context: context)
        } catch {
            assertionFailure("Failed to save image cache: \(error.localizedDescription)")
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
        index.aliases[requestedURL.absoluteString] = cacheKey
        index.aliases[responseURL.absoluteString] = cacheKey
        upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: byteCount)
        saveIndex()
        refreshAfterSaving(cacheKey: cacheKey, byteCount: byteCount, context: context)
    }

    /// Removes all cached image files from disk.
    func clear() {
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            index = ImageCacheIndex()
            contentDigestByCacheKey = [:]
            cacheKeyByContentDigest = [:]
            cacheFileSizeByKey = [:]
            snapshot = .empty
            gallerySummaries = []
        } catch {
            refresh()
        }
    }

    /// Removes cached image files and page records for one gallery.
    func clearGallery(_ identifier: EHGalleryIdentifier) {
        let removedRecords = index.pages.values.filter { $0.galleryIdentifier == identifier }
        guard !removedRecords.isEmpty || index.galleryMetadata[identifier.id] != nil else { return }

        let removedCacheKeys = Set(removedRecords.map(\.cacheKey))
        index.pages = index.pages.filter { $0.value.galleryIdentifier != identifier }
        index.galleryMetadata[identifier.id] = nil

        let remainingCacheKeys = Set(index.pages.values.map(\.cacheKey))
        let removableCacheKeys = removedCacheKeys.subtracting(remainingCacheKeys)
        index.aliases = index.aliases.filter { !removableCacheKeys.contains($0.value) }
        for cacheKey in removableCacheKeys {
            try? fileManager.removeItem(at: fileURL(forKey: cacheKey))
            if let digest = contentDigestByCacheKey.removeValue(forKey: cacheKey) {
                cacheKeyByContentDigest[digest] = nil
            }
            cacheFileSizeByKey[cacheKey] = nil
        }

        saveIndex()
        refresh(compactsDuplicates: false)
    }

    /// Returns true when cached image files are not tied to gallery reader pages.
    var hasNonGalleryImageCache: Bool {
        !nonGalleryCacheKeys().isEmpty
    }

    /// Removes search thumbnails, covers, and other image files not indexed as gallery pages.
    func clearNonGalleryImages() {
        let removableCacheKeys = nonGalleryCacheKeys()
        guard !removableCacheKeys.isEmpty else { return }

        index.aliases = index.aliases.filter { !removableCacheKeys.contains($0.value) }
        for cacheKey in removableCacheKeys {
            try? fileManager.removeItem(at: fileURL(forKey: cacheKey))
            if let digest = contentDigestByCacheKey.removeValue(forKey: cacheKey) {
                cacheKeyByContentDigest[digest] = nil
            }
            cacheFileSizeByKey[cacheKey] = nil
        }

        saveIndex()
        refresh(compactsDuplicates: false)
    }

    /// Recomputes cache usage stats from disk.
    func refresh(compactsDuplicates: Bool = false) {
        guard let allFileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            contentDigestByCacheKey = [:]
            cacheKeyByContentDigest = [:]
            cacheFileSizeByKey = [:]
            snapshot = .empty
            gallerySummaries = []
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
        gallerySummaries = makeGallerySummaries()
        snapshot = ImageCacheSnapshot(fileCount: uniqueFileCount, byteCount: uniqueByteCount, galleryCount: gallerySummaries.count)
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
            thumbnailURL: thumbnailURL,
            totalPageCount: context.totalPageCount ?? metadata?.totalPageCount,
            updatedAt: Date(),
            isDownloadUnavailable: metadata?.isDownloadUnavailable ?? false
        )
        index.aliases[requestedURL.absoluteString] = cacheKey
        index.aliases[responseURL.absoluteString] = cacheKey
    }

    /// Builds gallery summaries from indexed cached page records.
    private func makeGallerySummaries() -> [CachedGallerySummary] {
        Dictionary(grouping: Array(index.pages.values), by: \.galleryIdentifier)
            .map { identifier, records in
                let metadata = index.galleryMetadata[identifier.id]
                let sortedRecords = records.sorted { $0.pageNumber < $1.pageNumber }
                let uniqueCacheKeys = Set(records.map(\.cacheKey))
                let byteCount = uniqueCacheKeys.reduce(Int64(0)) { total, cacheKey in
                    total + (cacheFileSizeByKey[cacheKey] ?? 0)
                }
                return CachedGallerySummary(
                    galleryIdentifier: identifier,
                    title: metadata?.title ?? records.first?.galleryTitle ?? "图库 \(identifier.gid)",
                    thumbnailURL: metadata?.thumbnailURL ?? records.first?.thumbnailURL,
                    cachedPageCount: Set(records.map(\.pageNumber)).count,
                    totalPageCount: metadata?.totalPageCount ?? records.compactMap(\.totalPageCount).max(),
                    byteCount: byteCount,
                    updatedAt: records.map(\.updatedAt).max() ?? metadata?.updatedAt ?? .distantPast,
                    pageRecords: sortedRecords,
                    isDownloadUnavailable: metadata?.isDownloadUnavailable ?? false
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Loads the JSON index used for aliases and gallery summaries.

    /// Updates visible cache stats after saving one image without scanning every file.
    private func refreshAfterSaving(cacheKey: String, byteCount: Int64, context: ImageCacheContext?) {
        let previousByteCount = cacheFileSizeByKey[cacheKey]
        cacheFileSizeByKey[cacheKey] = byteCount
        let fileDelta = previousByteCount == nil ? 1 : 0
        let byteDelta = byteCount - (previousByteCount ?? 0)

        if context?.galleryIdentifier != nil {
            gallerySummaries = makeGallerySummaries()
        }
        snapshot = ImageCacheSnapshot(
            fileCount: max(0, snapshot.fileCount + fileDelta),
            byteCount: max(0, snapshot.byteCount + byteDelta),
            galleryCount: gallerySummaries.count
        )
    }

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

    /// Saves the JSON index next to cached data files.
    private func saveIndex() {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save image cache index: \(error.localizedDescription)")
        }
    }

    /// Picks a storage key while reusing legacy files and existing aliases.
    private func cacheKeyForSave(requestedURL: URL, responseURL: URL) -> String {
        if let key = index.aliases[responseURL.absoluteString] ?? index.aliases[requestedURL.absoluteString] {
            return key
        }
        if fileManager.fileExists(atPath: legacyFileURL(for: responseURL).path) {
            return cacheKey(for: responseURL)
        }
        if fileManager.fileExists(atPath: legacyFileURL(for: requestedURL).path) {
            return cacheKey(for: requestedURL)
        }
        return cacheKey(for: responseURL)
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
        diskCacheKeys().subtracting(Set(index.pages.values.map(\.cacheKey)))
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

    /// Builds a stable cache file URL for a cache key.

    /// Returns the byte size for one cached image file.

    /// Writes image bytes off the main actor to keep scrolling responsive.
    nonisolated private static func writeData(_ data: Data, to destinationURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            try data.write(to: destinationURL, options: [.atomic])
        }.value
    }

    private func fileSize(forKey key: String) -> Int64? {
        let values = try? fileURL(forKey: key).resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

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

    /// Builds a stable page index key.
    private func pageKey(identifier: EHGalleryIdentifier, pageNumber: Int) -> String {
        "\(identifier.id)-\(pageNumber)"
    }

    /// Hashes the full URL into a filesystem-safe cache key.
    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes file content so duplicate cache files count once in storage stats.

    /// Calculates a content digest away from the main actor for async save paths.
    nonisolated private static func contentDigestAsync(for data: Data) async -> String {
        await Task.detached(priority: .utility) {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

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

/// Downloads every reader image for a gallery into the shared cache.
@MainActor
final class GalleryDownloadManager: ObservableObject {
    static let shared = GalleryDownloadManager()

    @Published private(set) var progressByGalleryID: [String: GalleryDownloadProgress] = [:]
    @Published private(set) var aggregateProgress: GalleryDownloadAggregateProgress?

    private let client: any EHDataHTTPClient
    private let galleryParser: EHGalleryPageParser
    private let parser: EHImagePageParser
    private let cacheStore: ImageCacheStore
    private let hitomiDataSource: HitomiDataSource
    private let maxConcurrentDownloads: Int
    private let maxConcurrentPagesPerGallery: Int
    private let maxPageDownloadRetryCount: Int
    private let retryDelayRange: ClosedRange<Double>
    private var runningTasks: [String: Task<Void, Never>] = [:]
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
        self.maxPageDownloadRetryCount = max(0, maxPageDownloadRetryCount)
        self.retryDelayRange = retryDelayRange
    }

    /// Returns the latest progress for one gallery.
    func progress(for identifier: EHGalleryIdentifier) -> GalleryDownloadProgress? {
        guard let storedProgress = progressByGalleryID[identifier.id] else {
            return cachedProgress(for: identifier)
        }

        let cachedProgress = cachedProgress(for: identifier)
        let downloadedPageCount = cachedProgress?.downloadedPageCount ?? 0
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
        cacheStore.saveGalleryMetadata(detail: detail, fallback: fallback)
        let totalPageCount = detail.pageCount ?? detail.pageLinks.count
        progressByGalleryID[detail.identifier.id] = GalleryDownloadProgress(
            galleryID: detail.identifier.id,
            title: detail.title,
            downloadedPageCount: cachedPageCount(for: detail.identifier),
            totalPageCount: totalPageCount,
            isRunning: true,
            errorMessage: nil
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

    /// Starts queued downloads for every cached gallery whose cache is incomplete.
    func startUnfinishedDownloads(from summaries: [CachedGallerySummary]) {
        let unfinishedSummaries = summaries.filter { summary in
            guard let totalPageCount = summary.totalPageCount else { return false }
            return !summary.isDownloadUnavailable && summary.cachedPageCount < totalPageCount
        }

        for summary in unfinishedSummaries where !hasPendingOrRunningJob(for: summary.galleryIdentifier) {
            let totalPageCount = summary.totalPageCount ?? summary.cachedPageCount
            progressByGalleryID[summary.galleryIdentifier.id] = GalleryDownloadProgress(
                galleryID: summary.galleryIdentifier.id,
                title: summary.title,
                downloadedPageCount: summary.cachedPageCount,
                totalPageCount: totalPageCount,
                isRunning: true,
                errorMessage: nil
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
    }

    /// Pauses every queued or running gallery download.
    func pauseAllDownloads() {
        let affectedIDs = Set(queuedJobs.keys).union(runningTasks.keys)
        for task in runningTasks.values {
            task.cancel()
        }
        queuedJobs.removeAll()
        queuedJobIDs.removeAll()
        runningTasks.removeAll()

        for id in affectedIDs {
            guard let progress = progressByGalleryID[id] else { continue }
            progressByGalleryID[id] = GalleryDownloadProgress(
                galleryID: progress.galleryID,
                title: progress.title,
                downloadedPageCount: progress.downloadedPageCount,
                totalPageCount: progress.totalPageCount,
                isRunning: false,
                errorMessage: progress.errorMessage
            )
        }

        aggregateProgress = nil
        activeRunStartedAt = nil
        activeRunDownloadedByteCount = 0
    }

    /// Downloads reader images one page at a time.
    private func download(detail: EHGalleryDetail, fallback: EHSearchResult?) async {
        let totalPageCount = detail.pageCount ?? detail.pageLinks.count
        var downloadedPageCount = cachedPageCount(for: detail.identifier)
        var lastErrorMessage: String?
        updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: true, errorMessage: nil)

        let missingPageLinks = detail.pageLinks
            .sorted { $0.pageNumber < $1.pageNumber }
            .filter { pageLink in
                guard let record = cacheStore.pageRecord(for: detail.identifier, pageNumber: pageLink.pageNumber) else {
                    return true
                }
                return !cacheStore.containsData(for: record.imageURL)
            }

        if missingPageLinks.isEmpty {
            updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: false, errorMessage: nil)
            return
        }

        do {
            try await downloadMissingPages(missingPageLinks, detail: detail, fallback: fallback, totalPageCount: totalPageCount) { result in
                switch result.outcome {
                case .success(let byteCount):
                    recordDownloadedBytes(byteCount)
                    downloadedPageCount = cachedPageCount(for: detail.identifier)
                    updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: true, errorMessage: nil)
                case .failure(let error):
                    if error.isHTTPNotFound {
                        cacheStore.markGalleryDownloadUnavailable(
                            detail.identifier,
                            title: detail.title,
                            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL,
                            totalPageCount: totalPageCount
                        )
                    }
                    lastErrorMessage = String(format: AppCopy.galleryDownloadPageFailedFormat, String(result.pageNumber), error.localizedDescription)
                    updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: true, errorMessage: lastErrorMessage)
                }
            }
        } catch is CancellationError {
            updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: false, errorMessage: lastErrorMessage)
            return
        } catch {
            lastErrorMessage = error.localizedDescription
            updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: false, errorMessage: lastErrorMessage)
            return
        }

        updateProgress(detail: detail, downloadedPageCount: cachedPageCount(for: detail.identifier), totalPageCount: totalPageCount, isRunning: false, errorMessage: lastErrorMessage)
    }

    /// Updates observable progress for a gallery.
    private func updateProgress(detail: EHGalleryDetail, downloadedPageCount: Int, totalPageCount: Int, isRunning: Bool, errorMessage: String?) {
        progressByGalleryID[detail.identifier.id] = GalleryDownloadProgress(
            galleryID: detail.identifier.id,
            title: detail.title,
            downloadedPageCount: downloadedPageCount,
            totalPageCount: totalPageCount,
            isRunning: isRunning,
            errorMessage: errorMessage
        )
        updateAggregateProgress()
    }

    /// Builds progress from cache when no download is running.
    private func cachedProgress(for identifier: EHGalleryIdentifier) -> GalleryDownloadProgress? {
        guard let summary = cacheStore.gallerySummaries.first(where: { $0.galleryIdentifier == identifier }) else { return nil }
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
        cacheStore.gallerySummaries.first(where: { $0.galleryIdentifier == identifier })?.cachedPageCount ?? 0
    }

    /// Returns true when a gallery is already queued or actively downloading.
    private func hasPendingOrRunningJob(for identifier: EHGalleryIdentifier) -> Bool {
        runningTasks[identifier.id] != nil || queuedJobs[identifier.id] != nil
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
            runningTasks[nextID] = Task { [weak self] in
                await self?.run(job)
            }
        }
        updateAggregateProgress()
    }

    /// Runs one queued job and schedules the next job after it finishes.
    private func run(_ job: GalleryDownloadJob) async {
        defer {
            runningTasks[job.identifier.id] = nil
            scheduleDownloads()
        }

        do {
            let (detail, fallback) = try await resolvedDetailAndFallback(for: job)
            cacheStore.saveGalleryMetadata(detail: detail, fallback: fallback)
            await download(detail: detail, fallback: fallback)
        } catch is CancellationError {
            markJobPaused(job)
        } catch {
            if error.isHTTPNotFound {
                cacheStore.markGalleryDownloadUnavailable(job.identifier, title: job.title, totalPageCount: job.totalPageCount)
            }
            let downloadedPageCount = cachedPageCount(for: job.identifier)
            progressByGalleryID[job.identifier.id] = GalleryDownloadProgress(
                galleryID: job.identifier.id,
                title: job.title,
                downloadedPageCount: downloadedPageCount,
                totalPageCount: job.totalPageCount,
                isRunning: false,
                errorMessage: error.localizedDescription
            )
            updateAggregateProgress()
        }
    }

    /// Marks a cancelled job as paused instead of failed.
    private func markJobPaused(_ job: GalleryDownloadJob) {
        let progress = progressByGalleryID[job.identifier.id]
        progressByGalleryID[job.identifier.id] = GalleryDownloadProgress(
            galleryID: job.identifier.id,
            title: progress?.title ?? job.title,
            downloadedPageCount: cachedPageCount(for: job.identifier),
            totalPageCount: progress?.totalPageCount ?? job.totalPageCount,
            isRunning: false,
            errorMessage: progress?.errorMessage
        )
        updateAggregateProgress()
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
        onResult: @MainActor (GalleryPageDownloadResult) -> Void
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
                onResult(result)
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
            let byteCount = try await downloadPage(pageLink, detail: detail, fallback: fallback, totalPageCount: totalPageCount)
            return GalleryPageDownloadResult(pageNumber: pageLink.pageNumber, outcome: .success(byteCount))
        } catch {
            return GalleryPageDownloadResult(pageNumber: pageLink.pageNumber, outcome: .failure(error))
        }
    }

    private func downloadPage(
        _ pageLink: EHGalleryPageLink,
        detail: EHGalleryDetail,
        fallback: EHSearchResult?,
        totalPageCount: Int
    ) async throws -> Int64 {
        var lastError: Error?
        for attempt in 0...maxPageDownloadRetryCount {
            do {
                try Task.checkCancellation()
                return try await downloadPageOnce(pageLink, detail: detail, fallback: fallback, totalPageCount: totalPageCount)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if error.isHTTPNotFound {
                    break
                }
                guard attempt < maxPageDownloadRetryCount else { break }
                try await waitBeforeRetry()
            }
        }
        throw lastError ?? EHNetworkError.invalidResponse
    }

    /// Performs a single reader page and image download attempt.
    private func downloadPageOnce(
        _ pageLink: EHGalleryPageLink,
        detail: EHGalleryDetail,
        fallback: EHSearchResult?,
        totalPageCount: Int
    ) async throws -> Int64 {
        try Task.checkCancellation()
        let imagePage: EHImagePage
        if detail.identifier.site == .hitomi {
            imagePage = try await hitomiDataSource.imagePage(from: pageLink.pageURL)
        } else {
            let pageResponse = try await client.get(pageLink.pageURL)
            try Task.checkCancellation()
            imagePage = try parser.parse(pageResponse.body, sourceURL: pageResponse.url)
        }
        let imageReferer = detail.identifier.site == .hitomi ? (imagePage.galleryURL ?? imagePage.pageURL) : imagePage.pageURL
        let dataResponse = try await client.data(imagePage.imageURL, referer: imageReferer)
        try Task.checkCancellation()
        let context = ImageCacheContext(
            galleryIdentifier: detail.identifier,
            galleryTitle: detail.title,
            pageNumber: imagePage.pageNumber,
            pageURL: imagePage.pageURL,
            totalPageCount: totalPageCount,
            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL
        )
        await cacheStore.saveAsync(dataResponse.data, for: imagePage.imageURL, responseURL: dataResponse.url, context: context)
        return Int64(dataResponse.data.count)
    }

    /// Waits for a short randomized retry delay to avoid hammering the image host.
    private func waitBeforeRetry() async throws {
        let delay = Double.random(in: retryDelayRange)
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        guard nanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    /// Records bytes downloaded during the current active run.
    private func recordDownloadedBytes(_ byteCount: Int64) {
        if activeRunStartedAt == nil {
            activeRunStartedAt = Date()
        }
        activeRunDownloadedByteCount += byteCount
        updateAggregateProgress()
    }

    /// Publishes aggregate progress while at least one gallery download is active.
    private func updateAggregateProgress() {
        let activeDownloadCount = runningTasks.count
        guard activeDownloadCount > 0 else {
            aggregateProgress = nil
            activeRunStartedAt = nil
            activeRunDownloadedByteCount = 0
            return
        }

        if activeRunStartedAt == nil {
            activeRunStartedAt = Date()
            activeRunDownloadedByteCount = 0
        }

        let runningProgresses = progressByGalleryID.values.filter(\.isRunning)
        let downloadedPageCount = runningProgresses.reduce(0) { $0 + $1.downloadedPageCount }
        let totalPageCount = runningProgresses.reduce(0) { $0 + $1.totalPageCount }
        let elapsed = max(Date().timeIntervalSince(activeRunStartedAt ?? Date()), 0.1)
        let bytesPerSecond = Int64(Double(activeRunDownloadedByteCount) / elapsed)

        aggregateProgress = GalleryDownloadAggregateProgress(
            activeDownloadCount: activeDownloadCount,
            queuedDownloadCount: queuedJobs.count,
            downloadedPageCount: downloadedPageCount,
            totalPageCount: totalPageCount,
            bytesPerSecond: bytesPerSecond
        )
    }
}

/// Stores a queued gallery download request.

/// Stores the result for one downloaded gallery page.
private struct GalleryPageDownloadResult {
    let pageNumber: Int
    let outcome: Result<Int64, Error>
}

private struct GalleryDownloadJob {
    let identifier: EHGalleryIdentifier
    let title: String
    let totalPageCount: Int
    let source: GalleryDownloadJobSource
}

/// Describes how a queued download should resolve its page links.
private enum GalleryDownloadJobSource {
    case detail(EHGalleryDetail, EHSearchResult?)
    case cachedSummary(CachedGallerySummary)
}

/// Stores cache aliases and reader page mappings.
private struct ImageCacheIndex: Codable {
    var aliases: [String: String] = [:]
    var pages: [String: CachedImagePageRecord] = [:]
    var galleryMetadata: [String: CachedGalleryMetadata] = [:]
}

/// Stores gallery-level metadata for partially indexed caches.
private struct CachedGalleryMetadata: Codable, Hashable {
    let identifier: EHGalleryIdentifier
    let title: String
    let thumbnailURL: URL?
    let totalPageCount: Int?
    let updatedAt: Date
    let isDownloadUnavailable: Bool

    /// Creates metadata and defaults the download marker to available.
    init(
        identifier: EHGalleryIdentifier,
        title: String,
        thumbnailURL: URL?,
        totalPageCount: Int?,
        updatedAt: Date,
        isDownloadUnavailable: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
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
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        totalPageCount = try container.decodeIfPresent(Int.self, forKey: .totalPageCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isDownloadUnavailable = try container.decodeIfPresent(Bool.self, forKey: .isDownloadUnavailable) ?? false
    }
}
