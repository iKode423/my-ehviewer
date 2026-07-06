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

/// Default URLSession-backed HTTP client used by the app.
@MainActor
final class URLSessionEHHTTPClient: EHHTTPClient {
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
}

/// Describes current disk usage for cached remote images.
struct ImageCacheSnapshot: Equatable {
    let fileCount: Int
    let byteCount: Int64

    static let empty = ImageCacheSnapshot(fileCount: 0, byteCount: 0)

    var isEmpty: Bool {
        fileCount == 0
    }

    var localizedByteCount: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// Stores viewed image data on disk so reader pages can reopen without refetching.
@MainActor
final class ImageCacheStore: ObservableObject {
    static let shared = ImageCacheStore()

    @Published private(set) var snapshot: ImageCacheSnapshot = .empty

    private let directoryURL: URL
    private let fileManager: FileManager

    /// Creates a cache store rooted in the app caches directory by default.
    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
            self.directoryURL = baseURL.appending(path: "ImageCache", directoryHint: .isDirectory)
        }
        refresh()
    }

    /// Returns cached image data for the remote URL when it exists.
    func data(for url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url))
    }

    /// Saves image data and refreshes cache usage stats.
    func save(_ data: Data, for url: URL) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: url), options: [.atomic])
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
            snapshot = .empty
        } catch {
            refresh()
        }
    }

    /// Recomputes cache usage stats from disk.
    func refresh() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            snapshot = .empty
            return
        }

        let byteCount = fileURLs.reduce(Int64(0)) { total, fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values?.fileSize ?? 0)
        }
        snapshot = ImageCacheSnapshot(fileCount: fileURLs.count, byteCount: byteCount)
    }

    /// Builds a stable cache file URL for one remote image URL.
    private func fileURL(for url: URL) -> URL {
        directoryURL.appending(path: cacheKey(for: url), directoryHint: .notDirectory)
    }

    /// Hashes the full URL into a filesystem-safe cache key.
    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
