import Combine
import Foundation

/// Loads and stores one gallery detail page.
@MainActor
final class GalleryDetailViewModel: ObservableObject {
    @Published private(set) var detail: EHGalleryDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let pageURL: URL
    private let client: EHHTTPClient
    private let parser: EHGalleryPageParser

    /// Creates a view model for one gallery URL.
    init(
        pageURL: URL,
        client: EHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHGalleryPageParser = EHGalleryPageParser()
    ) {
        self.pageURL = pageURL
        self.client = client
        self.parser = parser
    }

    /// Loads the detail page only when no detail has been loaded yet.
    func loadIfNeeded() async {
        guard detail == nil else { return }
        await reload()
    }

    /// Reloads the detail page from the network.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.get(pageURL)
            detail = try parser.parse(response.body, sourceURL: response.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

