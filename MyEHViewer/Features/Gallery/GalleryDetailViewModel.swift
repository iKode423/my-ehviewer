import Combine
import Foundation

/// Loads and stores one gallery detail page.
@MainActor
final class GalleryDetailViewModel: ObservableObject {
    @Published private(set) var detail: EHGalleryDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMorePageLinks = false
    @Published private(set) var errorMessage: String?

    private let pageURL: URL
    private let client: EHHTTPClient
    private let parser: EHGalleryPageParser
    private var loadedThumbnailPageURLStrings: Set<String> = []

    var canLoadMorePageLinks: Bool {
        !remainingThumbnailPageURLs.isEmpty
    }

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
            loadedThumbnailPageURLStrings = [response.url.absoluteString]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the next known thumbnail page and merges its reader links.
    func loadMorePageLinks() async {
        guard
            !isLoadingMorePageLinks,
            let nextURL = remainingThumbnailPageURLs.first,
            let currentDetail = detail
        else {
            return
        }

        isLoadingMorePageLinks = true
        errorMessage = nil
        defer { isLoadingMorePageLinks = false }

        do {
            let response = try await client.get(nextURL)
            let incomingDetail = try parser.parse(response.body, sourceURL: response.url)
            loadedThumbnailPageURLStrings.insert(response.url.absoluteString)
            detail = mergedDetail(currentDetail, with: incomingDetail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns thumbnail page URLs that have not been fetched yet.
    private var remainingThumbnailPageURLs: [URL] {
        detail?.thumbnailPageURLs.filter { !loadedThumbnailPageURLStrings.contains($0.absoluteString) } ?? []
    }

    /// Combines reader links and pagination URLs while preserving primary metadata.
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
            thumbnailPageURLs: thumbnailPageURLs
        )
    }
}
