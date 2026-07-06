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

/// Loads public HTML pages while preserving cookies in the shared URL session.
@MainActor
protocol EHHTTPClient {
    /// Sends a GET request and returns the decoded HTML body.
    func get(_ url: URL) async throws -> EHHTTPResponse
}

/// Submits URL-encoded site forms while preserving cookies.
@MainActor
protocol EHFormHTTPClient {
    /// Sends a POST request and returns the decoded HTML body.
    func postForm(_ url: URL, fields: [String: String]) async throws -> EHHTTPResponse
}

/// Default URLSession-backed HTTP client used by the app.
@MainActor
final class URLSessionEHHTTPClient: EHHTTPClient, EHFormHTTPClient {
    private let session: URLSession
    private let cookieHeaderProvider: @MainActor () -> String?

    /// Creates a client with browser-like headers that the public site accepts.
    init(
        session: URLSession = .shared,
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
        let (data, httpResponse) = try await responseData(for: makeRequest(url, accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"))
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
    private func makeRequest(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 MyEHViewer/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let cookieHeader = cookieHeaderProvider(), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return request
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
        refresh()
    }

    /// Returns cached image data for the remote URL when it exists.
    func data(for url: URL) -> Data? {
        if let cacheKey = index.aliases[url.absoluteString],
           let data = try? Data(contentsOf: fileURL(forKey: cacheKey)) {
            return data
        }
        return try? Data(contentsOf: legacyFileURL(for: url))
    }

    /// Returns true when image data exists for a URL.
    func containsData(for url: URL) -> Bool {
        data(for: url) != nil
    }

    /// Returns a cached reader page for a specific reader URL.
    func pageRecord(for pageURL: URL) -> CachedImagePageRecord? {
        index.pages.values.first { $0.pageURL == pageURL }
    }

    /// Returns a cached reader page for a gallery page number.
    func pageRecord(for identifier: EHGalleryIdentifier, pageNumber: Int) -> CachedImagePageRecord? {
        index.pages[pageKey(identifier: identifier, pageNumber: pageNumber)]
    }

    /// Stores gallery metadata so cache management can list partially downloaded galleries.
    func saveGalleryMetadata(detail: EHGalleryDetail, fallback: EHSearchResult? = nil) {
        index.galleryMetadata[detail.identifier.id] = CachedGalleryMetadata(
            identifier: detail.identifier,
            title: detail.title,
            thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL,
            totalPageCount: detail.pageCount,
            updatedAt: Date()
        )
        saveIndex()
        refresh()
    }

    /// Saves image data and refreshes cache usage stats.
    func save(_ data: Data, for url: URL) {
        save(data, for: url, responseURL: url, context: nil)
    }

    /// Saves image data with aliases and optional gallery page metadata.
    func save(_ data: Data, for requestedURL: URL, responseURL: URL, context: ImageCacheContext?) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var cacheKey = cacheKeyForSave(requestedURL: requestedURL, responseURL: responseURL)
            var destinationURL = fileURL(forKey: cacheKey)
            if !fileManager.fileExists(atPath: destinationURL.path),
               let existingCacheKey = cacheKeyForExistingContent(matching: data) {
                cacheKey = existingCacheKey
                destinationURL = fileURL(forKey: existingCacheKey)
            }
            if !fileManager.fileExists(atPath: destinationURL.path) {
                try data.write(to: destinationURL, options: [.atomic])
            }

            index.aliases[requestedURL.absoluteString] = cacheKey
            index.aliases[responseURL.absoluteString] = cacheKey
            upsertPageRecord(context: context, requestedURL: requestedURL, responseURL: responseURL, cacheKey: cacheKey, byteCount: Int64(data.count))
            saveIndex()
            refresh()
        } catch {
            assertionFailure("Failed to save image cache: \(error.localizedDescription)")
        }
    }

    /// Removes all cached image files from disk.
    func clear() {
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            index = ImageCacheIndex()
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
        }

        saveIndex()
        refresh()
    }

    /// Recomputes cache usage stats from disk.
    func refresh() {
        guard let allFileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            snapshot = .empty
            gallerySummaries = []
            return
        }

        let fileURLs = allFileURLs.filter { $0.lastPathComponent != indexFileName }
        var canonicalKeysByDigest: [String: String] = [:]
        var duplicateKeyMap: [String: String] = [:]
        var uniqueFileCount = 0
        var uniqueByteCount: Int64 = 0
        for fileURL in fileURLs {
            guard let digest = contentDigest(for: fileURL) else { continue }
            let cacheKey = fileURL.lastPathComponent
            if let canonicalKey = canonicalKeysByDigest[digest] {
                duplicateKeyMap[cacheKey] = canonicalKey
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            canonicalKeysByDigest[digest] = cacheKey
            uniqueFileCount += 1
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            uniqueByteCount += Int64(values?.fileSize ?? 0)
        }
        if !duplicateKeyMap.isEmpty {
            remapIndexCacheKeys(duplicateKeyMap)
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
            updatedAt: Date()
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
                    let values = try? fileURL(forKey: cacheKey).resourceValues(forKeys: [.fileSizeKey])
                    return total + Int64(values?.fileSize ?? 0)
                }
                return CachedGallerySummary(
                    galleryIdentifier: identifier,
                    title: metadata?.title ?? records.first?.galleryTitle ?? "图库 \(identifier.gid)",
                    thumbnailURL: metadata?.thumbnailURL ?? records.first?.thumbnailURL,
                    cachedPageCount: Set(records.map(\.pageNumber)).count,
                    totalPageCount: metadata?.totalPageCount ?? records.compactMap(\.totalPageCount).max(),
                    byteCount: byteCount,
                    updatedAt: records.map(\.updatedAt).max() ?? metadata?.updatedAt ?? .distantPast,
                    pageRecords: sortedRecords
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
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
    private func cacheKeyForExistingContent(matching data: Data) -> String? {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let targetDigest = contentDigest(for: data)
        return fileURLs
            .filter { $0.lastPathComponent != indexFileName }
            .first { contentDigest(for: $0) == targetDigest }?
            .lastPathComponent
    }

    /// Points aliases and page records at canonical cache files after duplicate cleanup.
    private func remapIndexCacheKeys(_ replacements: [String: String]) {
        index.aliases = index.aliases.mapValues { replacements[$0] ?? $0 }
        for pageKey in Array(index.pages.keys) {
            guard var record = index.pages[pageKey], let replacement = replacements[record.cacheKey] else { continue }
            record.cacheKey = replacement
            index.pages[pageKey] = record
        }
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

/// Downloads every reader image for a gallery into the shared cache.
@MainActor
final class GalleryDownloadManager: ObservableObject {
    static let shared = GalleryDownloadManager()

    @Published private(set) var progressByGalleryID: [String: GalleryDownloadProgress] = [:]

    private let client: URLSessionEHHTTPClient
    private let parser: EHImagePageParser
    private let cacheStore: ImageCacheStore
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Creates a download manager with injectable dependencies.
    init(
        client: URLSessionEHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHImagePageParser = EHImagePageParser(),
        cacheStore: ImageCacheStore = .shared
    ) {
        self.client = client
        self.parser = parser
        self.cacheStore = cacheStore
    }

    /// Returns the latest progress for one gallery.
    func progress(for identifier: EHGalleryIdentifier) -> GalleryDownloadProgress? {
        progressByGalleryID[identifier.id] ?? cachedProgress(for: identifier)
    }

    /// Starts a non-blocking download for all currently known gallery page links.
    func startDownload(detail: EHGalleryDetail, fallback: EHSearchResult? = nil) {
        guard tasks[detail.identifier.id] == nil else { return }
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

        tasks[detail.identifier.id] = Task { [weak self] in
            await self?.download(detail: detail, fallback: fallback)
        }
    }

    /// Downloads reader images one page at a time.
    private func download(detail: EHGalleryDetail, fallback: EHSearchResult?) async {
        let totalPageCount = detail.pageCount ?? detail.pageLinks.count
        var downloadedPageCount = cachedPageCount(for: detail.identifier)
        updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: true, errorMessage: nil)

        for pageLink in detail.pageLinks.sorted(by: { $0.pageNumber < $1.pageNumber }) {
            if let record = cacheStore.pageRecord(for: detail.identifier, pageNumber: pageLink.pageNumber),
               cacheStore.containsData(for: record.imageURL) {
                downloadedPageCount = max(downloadedPageCount, cachedPageCount(for: detail.identifier))
                updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: true, errorMessage: nil)
                continue
            }

            do {
                let pageResponse = try await client.get(pageLink.pageURL)
                let imagePage = try parser.parse(pageResponse.body, sourceURL: pageResponse.url)
                let dataResponse = try await client.data(imagePage.imageURL)
                let context = ImageCacheContext(
                    galleryIdentifier: detail.identifier,
                    galleryTitle: detail.title,
                    pageNumber: imagePage.pageNumber,
                    pageURL: imagePage.pageURL,
                    totalPageCount: totalPageCount,
                    thumbnailURL: detail.coverURL ?? fallback?.thumbnailURL
                )
                cacheStore.save(dataResponse.data, for: imagePage.imageURL, responseURL: dataResponse.url, context: context)
                downloadedPageCount = cachedPageCount(for: detail.identifier)
                updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: true, errorMessage: nil)
            } catch {
                updateProgress(detail: detail, downloadedPageCount: downloadedPageCount, totalPageCount: totalPageCount, isRunning: false, errorMessage: error.localizedDescription)
                tasks[detail.identifier.id] = nil
                return
            }
        }

        updateProgress(detail: detail, downloadedPageCount: cachedPageCount(for: detail.identifier), totalPageCount: totalPageCount, isRunning: false, errorMessage: nil)
        tasks[detail.identifier.id] = nil
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
}
