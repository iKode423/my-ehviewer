import Foundation

/// Represents a text response returned by the E-Hentai website.
struct EHHTTPResponse: Hashable {
    let url: URL
    let statusCode: Int
    let body: String
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

    /// Creates a client with browser-like headers that the public site accepts.
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends a GET request using a stable user agent and Chinese language preference.
    func get(_ url: URL) async throws -> EHHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 MyEHViewer/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EHNetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw EHNetworkError.unacceptableStatusCode(httpResponse.statusCode)
        }

        if let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return EHHTTPResponse(url: httpResponse.url ?? url, statusCode: httpResponse.statusCode, body: body)
        }

        throw EHNetworkError.undecodableBody
    }
}
