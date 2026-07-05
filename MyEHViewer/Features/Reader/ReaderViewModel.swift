import Combine
import Foundation

/// Loads image reader pages and tracks page navigation state.
@MainActor
final class ReaderViewModel: ObservableObject {
    let initialPageURL: URL?

    @Published private(set) var imagePage: EHImagePage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: EHHTTPClient
    private let parser: EHImagePageParser
    private var currentPageURL: URL?

    var canLoadPreviousPage: Bool {
        guard let previousPageURL = imagePage?.previousPageURL else { return false }
        return previousPageURL != currentPageURL
    }

    var canLoadNextPage: Bool {
        guard let nextPageURL = imagePage?.nextPageURL else { return false }
        return nextPageURL != currentPageURL
    }

    /// Creates a reader view model with injectable dependencies for tests.
    init(
        initialPageURL: URL?,
        client: EHHTTPClient = URLSessionEHHTTPClient(),
        parser: EHImagePageParser = EHImagePageParser()
    ) {
        self.initialPageURL = initialPageURL
        self.currentPageURL = initialPageURL
        self.client = client
        self.parser = parser
    }

    /// Loads the initial page if the reader has not loaded it yet.
    func loadIfNeeded() async {
        guard imagePage == nil else { return }
        await reload()
    }

    /// Reloads the current page URL.
    func reload() async {
        guard let currentPageURL else { return }
        await load(currentPageURL)
    }

    /// Loads the previous image page when available.
    func loadPreviousPage() async {
        guard canLoadPreviousPage, let previousPageURL = imagePage?.previousPageURL else { return }
        await load(previousPageURL)
    }

    /// Loads the next image page when available.
    func loadNextPage() async {
        guard canLoadNextPage, let nextPageURL = imagePage?.nextPageURL else { return }
        await load(nextPageURL)
    }

    /// Fetches, parses, and stores one reader page.
    private func load(_ url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.get(url)
            imagePage = try parser.parse(response.body, sourceURL: response.url)
            currentPageURL = response.url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

