import Combine
import Foundation

/// Stores local history, favorites, and reading progress without caching remote content.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var records: [LibraryGalleryRecord] = []
    @Published private(set) var favoriteIDs: Set<String> = []

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
        } else {
            records.append(LibraryGalleryRecord(imagePage: imagePage, identifier: identifier))
        }
        save()
    }

    /// Removes all local library state.
    func removeAll() {
        records = []
        favoriteIDs = []
        save()
    }

    /// Removes local library state for one content site.
    func removeAll(for site: ContentSite) {
        let removedIDs = Set(records.filter { $0.identifier.site == site }.map(\.id))
        records.removeAll { $0.identifier.site == site }
        favoriteIDs.subtract(removedIDs)
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
        save()
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
    }

    /// Saves JSON state to UserDefaults.
    private func save() {
        let state = LibraryState(records: records, favoriteIDs: Array(favoriteIDs))
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

/// Stores the full persisted library payload.
private struct LibraryState: Codable {
    let records: [LibraryGalleryRecord]
    let favoriteIDs: [String]
}
