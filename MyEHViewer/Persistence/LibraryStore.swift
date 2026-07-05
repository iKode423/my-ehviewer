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
            let identifier = EHGalleryIdentifier(galleryURL: galleryURL),
            let index = records.firstIndex(where: { $0.identifier == identifier })
        else {
            return
        }

        records[index].lastReadPage = imagePage.pageNumber
        records[index].lastReadPageURL = imagePage.pageURL
        records[index].lastOpenedAt = Date()
        save()
    }

    /// Removes all local library state.
    func removeAll() {
        records = []
        favoriteIDs = []
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
            tags: []
        )
    }

    /// Creates a local record from parsed detail and fallback search data.
    init(detail: EHGalleryDetail, fallback: EHSearchResult, existing: LibraryGalleryRecord?) {
        self.identifier = detail.identifier
        self.title = detail.title
        self.category = detail.category
        self.pageURL = detail.identifier.url()
        self.thumbnailURL = detail.coverURL ?? fallback.thumbnailURL
        self.uploader = detail.uploader ?? fallback.uploader
        self.pageCountText = detail.metadata.first { $0.key.lowercased().contains("length") }?.value ?? fallback.pageCountText
        self.lastOpenedAt = Date()
        self.lastReadPage = existing?.lastReadPage
        self.lastReadPageURL = existing?.lastReadPageURL
    }
}

/// Stores the full persisted library payload.
private struct LibraryState: Codable {
    let records: [LibraryGalleryRecord]
    let favoriteIDs: [String]
}
