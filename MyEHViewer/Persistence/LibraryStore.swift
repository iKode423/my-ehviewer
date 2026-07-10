import Combine
import Foundation

/// Stores local history, favorites, and reading progress without caching remote content.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var records: [LibraryGalleryRecord] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var imageFavorites: [FavoriteImageRecord] = []
    @Published private(set) var combinedImageFavoriteOrder: [String] = []

    private let userDefaults: UserDefaults
    private let storageKey: String

    var favorites: [LibraryGalleryRecord] {
        sortedRecords.filter { favoriteIDs.contains($0.id) }
    }

    var history: [LibraryGalleryRecord] {
        sortedRecords
    }

    /// Returns local favorites for one content site.
    func favorites(for site: ContentSite) -> [LibraryGalleryRecord] {
        favorites.filter { $0.identifier.site == site }
    }

    /// Returns reading history for one content site.
    func history(for site: ContentSite) -> [LibraryGalleryRecord] {
        history.filter { $0.identifier.site == site }
    }

    private var sortedRecords: [LibraryGalleryRecord] {
        records.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Creates a store backed by a configurable UserDefaults instance.
    init(userDefaults: UserDefaults = .standard, storageKey: String = "LibraryStore.v1") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        load()
    }

    /// Returns true when a gallery is currently marked as favorite.
    func isFavorite(_ identifier: EHGalleryIdentifier) -> Bool {
        favoriteIDs.contains(identifier.id)
    }

    /// Records that a gallery detail page was opened.
    func record(detail: EHGalleryDetail, fallback: EHSearchResult) {
        upsert(record: LibraryGalleryRecord(detail: detail, fallback: fallback, existing: record(for: detail.identifier)))
    }

    /// Toggles favorite state and ensures the gallery exists in local records.
    func toggleFavorite(detail: EHGalleryDetail, fallback: EHSearchResult) {
        record(detail: detail, fallback: fallback)
        if favoriteIDs.contains(detail.identifier.id) {
            favoriteIDs.remove(detail.identifier.id)
        } else {
            favoriteIDs.insert(detail.identifier.id)
        }
        save()
    }

    /// Updates reading progress from a loaded image page.
    func updateProgress(imagePage: EHImagePage) {
        guard
            let galleryURL = imagePage.galleryURL,
            let identifier = EHGalleryIdentifier(galleryURL: galleryURL)
        else {
            return
        }

        if let index = records.firstIndex(where: { $0.identifier == identifier }) {
            records[index].lastReadPage = imagePage.pageNumber
            records[index].lastReadPageURL = imagePage.pageURL
            records[index].lastOpenedAt = Date()
            updateFavoriteImageGalleryTitle(for: records[index])
        } else {
            let record = LibraryGalleryRecord(imagePage: imagePage, identifier: identifier)
            records.append(record)
            updateFavoriteImageGalleryTitle(for: record)
        }
        save()
    }

    /// Returns true when the loaded reader page is an image favorite.
    func isImageFavorite(_ imagePage: EHImagePage) -> Bool {
        imageFavorites.contains { $0.pageURL == imagePage.pageURL }
    }

    /// Toggles the image favorite state for the loaded reader page.
    func toggleImageFavorite(imagePage: EHImagePage) {
        guard
            let galleryURL = imagePage.galleryURL,
            let identifier = EHGalleryIdentifier(galleryURL: galleryURL)
        else {
            return
        }

        if let index = imageFavorites.firstIndex(where: { $0.pageURL == imagePage.pageURL }) {
            imageFavorites.remove(at: index)
        } else {
            let galleryTitle = record(for: identifier)?.title ?? imagePage.title ?? "图库 \(identifier.gid)"
            imageFavorites.insert(
                FavoriteImageRecord(
                    imagePage: imagePage,
                    galleryIdentifier: identifier,
                    galleryTitle: galleryTitle
                ),
                at: 0
            )
        }
        save()
    }

    /// Moves an image favorite one position for manual sorting.
    func moveImageFavorite(_ favorite: FavoriteImageRecord, direction: Int) {
        guard
            direction != 0,
            let index = imageFavorites.firstIndex(where: { $0.id == favorite.id })
        else {
            return
        }
        let targetIndex = max(0, min(imageFavorites.count - 1, index + direction))
        guard targetIndex != index else { return }
        imageFavorites.swapAt(index, targetIndex)
        save()
    }

    /// Moves an image favorite to the first position in the custom order.
    func moveImageFavoriteToFront(_ favorite: FavoriteImageRecord) {
        guard
            let index = imageFavorites.firstIndex(where: { $0.id == favorite.id }),
            index > 0
        else {
            return
        }
        let movedFavorite = imageFavorites.remove(at: index)
        imageFavorites.insert(movedFavorite, at: 0)
        save()
    }

    /// Resolves one stable order across gallery and shared image favorites.
    func orderedImageFavoriteIDs(availableIDs: [String]) -> [String] {
        let availableSet = Set(availableIDs)
        let stored = combinedImageFavoriteOrder.filter { availableSet.contains($0) }
        let missing = availableIDs.filter { !stored.contains($0) }
        return stored + missing
    }

    /// Moves one combined image favorite by a relative position.
    func moveCombinedImageFavorite(id: String, direction: Int, availableIDs: [String]) {
        guard direction != 0 else { return }
        var order = orderedImageFavoriteIDs(availableIDs: availableIDs)
        guard let index = order.firstIndex(of: id) else { return }
        let target = max(0, min(order.count - 1, index + direction))
        guard target != index else { return }
        order.swapAt(index, target)
        combinedImageFavoriteOrder = order
        save()
    }

    /// Moves one combined image favorite to the first visible position.
    func moveCombinedImageFavoriteToFront(id: String, availableIDs: [String]) {
        var order = orderedImageFavoriteIDs(availableIDs: availableIDs)
        guard let index = order.firstIndex(of: id), index > 0 else { return }
        let movedID = order.remove(at: index)
        order.insert(movedID, at: 0)
        combinedImageFavoriteOrder = order
        save()
    }

    /// Encodes history and favorites into a portable JSON backup.
    func exportData() throws -> Data {
        let state = LibraryState(
            records: records,
            favoriteIDs: Array(favoriteIDs),
            imageFavorites: imageFavorites,
            combinedImageFavoriteOrder: combinedImageFavoriteOrder
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    /// Replaces history and favorites with a decoded JSON backup.
    func importData(_ data: Data) throws {
        let state = try JSONDecoder().decode(LibraryState.self, from: data)
        records = state.records
        favoriteIDs = Set(state.favoriteIDs)
        imageFavorites = state.imageFavorites
        combinedImageFavoriteOrder = state.combinedImageFavoriteOrder
        save()
    }

    /// Removes all local library state.
    func removeAll() {
        records = []
        favoriteIDs = []
        imageFavorites = []
        combinedImageFavoriteOrder = []
        save()
    }

    /// Removes local library state for one content site.
    func removeAll(for site: ContentSite) {
        let removedIDs = Set(records.filter { $0.identifier.site == site }.map(\.id))
        records.removeAll { $0.identifier.site == site }
        favoriteIDs.subtract(removedIDs)
        imageFavorites.removeAll { $0.galleryIdentifier.site == site }
        save()
    }

    /// Finds a record for the given gallery identifier.
    func record(for identifier: EHGalleryIdentifier) -> LibraryGalleryRecord? {
        records.first { $0.identifier == identifier }
    }

    /// Inserts or updates one gallery record.
    private func upsert(record: LibraryGalleryRecord) {
        if let index = records.firstIndex(where: { $0.identifier == record.identifier }) {
            records[index] = record
        } else {
            records.append(record)
        }
        updateFavoriteImageGalleryTitle(for: record)
        save()
    }

    /// Keeps image favorite captions aligned with the latest gallery title.
    private func updateFavoriteImageGalleryTitle(for record: LibraryGalleryRecord) {
        for index in imageFavorites.indices where imageFavorites[index].galleryIdentifier == record.identifier {
            imageFavorites[index].galleryTitle = record.title
        }
    }

    /// Loads JSON state from UserDefaults.
    private func load() {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let state = try? JSONDecoder().decode(LibraryState.self, from: data)
        else {
            return
        }
        records = state.records
        favoriteIDs = Set(state.favoriteIDs)
        imageFavorites = state.imageFavorites
        combinedImageFavoriteOrder = state.combinedImageFavoriteOrder
    }

    /// Saves JSON state to UserDefaults.
    private func save() {
        let state = LibraryState(
            records: records,
            favoriteIDs: Array(favoriteIDs),
            imageFavorites: imageFavorites,
            combinedImageFavoriteOrder: combinedImageFavoriteOrder
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

/// Represents one locally tracked gallery.
struct LibraryGalleryRecord: Codable, Hashable, Identifiable {
    let identifier: EHGalleryIdentifier
    var title: String
    var category: String
    var pageURL: URL
    var thumbnailURL: URL?
    var uploader: String?
    var pageCountText: String?
    var tags: [EHTag]
    var lastOpenedAt: Date
    var lastReadPage: Int?
    var lastReadPageURL: URL?

    var id: String { identifier.id }

    var searchResult: EHSearchResult {
        EHSearchResult(
            identifier: identifier,
            title: title,
            category: category,
            pageURL: pageURL,
            thumbnailURL: thumbnailURL,
            uploader: uploader,
            postedText: nil,
            pageCountText: pageCountText,
            tags: tags
        )
    }

    var pageCount: Int? {
        pageCountText
            .flatMap { EHHTMLParsing.firstMatch(in: $0, pattern: #"([0-9]+)\s*pages?"#)?.dropFirst().first }
            .flatMap(Int.init)
    }

    /// Creates a local record from parsed detail and fallback search data.
    init(detail: EHGalleryDetail, fallback: EHSearchResult, existing: LibraryGalleryRecord?) {
        self.identifier = detail.identifier
        self.title = detail.title
        self.category = detail.category
        self.pageURL = detail.identifier.url()
        self.thumbnailURL = detail.coverURL ?? fallback.thumbnailURL
        self.uploader = detail.uploader ?? fallback.uploader
        self.pageCountText = detail.pageCount.map { "\($0) pages" } ?? detail.metadata.first { $0.key.lowercased().contains("length") }?.value ?? fallback.pageCountText
        self.tags = detail.tags.isEmpty ? fallback.tags : detail.tags
        self.lastOpenedAt = Date()
        self.lastReadPage = existing?.lastReadPage
        self.lastReadPageURL = existing?.lastReadPageURL
    }

    /// Creates a minimal local record from reader progress.
    init(imagePage: EHImagePage, identifier: EHGalleryIdentifier) {
        self.identifier = identifier
        self.title = imagePage.title ?? "图库 \(identifier.gid)"
        self.category = ""
        self.pageURL = identifier.url()
        self.thumbnailURL = nil
        self.uploader = nil
        self.pageCountText = nil
        self.tags = []
        self.lastOpenedAt = Date()
        self.lastReadPage = imagePage.pageNumber
        self.lastReadPageURL = imagePage.pageURL
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case title
        case category
        case pageURL
        case thumbnailURL
        case uploader
        case pageCountText
        case tags
        case lastOpenedAt
        case lastReadPage
        case lastReadPageURL
    }

    /// Decodes older records that did not persist parsed gallery tags.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(EHGalleryIdentifier.self, forKey: .identifier)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        pageCountText = try container.decodeIfPresent(String.self, forKey: .pageCountText)
        tags = try container.decodeIfPresent([EHTag].self, forKey: .tags) ?? []
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        lastReadPage = try container.decodeIfPresent(Int.self, forKey: .lastReadPage)
        lastReadPageURL = try container.decodeIfPresent(URL.self, forKey: .lastReadPageURL)
    }

    /// Encodes library records with parsed tags for local statistics.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(pageURL, forKey: .pageURL)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encodeIfPresent(uploader, forKey: .uploader)
        try container.encodeIfPresent(pageCountText, forKey: .pageCountText)
        try container.encode(tags, forKey: .tags)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encodeIfPresent(lastReadPage, forKey: .lastReadPage)
        try container.encodeIfPresent(lastReadPageURL, forKey: .lastReadPageURL)
    }
}

struct FavoriteImageRecord: Codable, Hashable, Identifiable {
    let galleryIdentifier: EHGalleryIdentifier
    var galleryTitle: String
    let pageNumber: Int
    let pageURL: URL
    let imageURL: URL
    let originalImageURL: URL?
    let createdAt: Date

    var id: String { pageURL.absoluteString }

    /// Creates a favorite image record from the current reader page.
    init(imagePage: EHImagePage, galleryIdentifier: EHGalleryIdentifier, galleryTitle: String) {
        self.galleryIdentifier = galleryIdentifier
        self.galleryTitle = galleryTitle
        self.pageNumber = imagePage.pageNumber
        self.pageURL = imagePage.pageURL
        self.imageURL = imagePage.imageURL
        self.originalImageURL = imagePage.originalImageURL
        self.createdAt = Date()
    }
}

/// Stores the full persisted library payload.
private struct LibraryState: Codable {
    let records: [LibraryGalleryRecord]
    let favoriteIDs: [String]
    let imageFavorites: [FavoriteImageRecord]
    let combinedImageFavoriteOrder: [String]

    /// Creates persisted library state with optional image favorites and combined ordering.
    init(
        records: [LibraryGalleryRecord],
        favoriteIDs: [String],
        imageFavorites: [FavoriteImageRecord] = [],
        combinedImageFavoriteOrder: [String] = []
    ) {
        self.records = records
        self.favoriteIDs = favoriteIDs
        self.imageFavorites = imageFavorites
        self.combinedImageFavoriteOrder = combinedImageFavoriteOrder
    }

    /// Decodes older library state that did not contain image favorites or combined ordering.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([LibraryGalleryRecord].self, forKey: .records)
        favoriteIDs = try container.decode([String].self, forKey: .favoriteIDs)
        imageFavorites = try container.decodeIfPresent([FavoriteImageRecord].self, forKey: .imageFavorites) ?? []
        combinedImageFavoriteOrder = try container.decodeIfPresent([String].self, forKey: .combinedImageFavoriteOrder) ?? []
    }
}
