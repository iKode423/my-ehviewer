import Foundation

/// Identifies the persistent media type shared into the app.
enum SharedMediaKind: String, Codable, CaseIterable, Identifiable {
    case image
    case video

    var id: String { rawValue }
}

/// Selects a list or adaptive grid presentation for collection screens.
enum CollectionLayoutMode: String, Codable, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
}

/// Stores one file copied by the Share Extension into the incoming area.
struct SharedMediaIncomingItem: Codable, Hashable, Identifiable {
    let id: UUID
    let kind: SharedMediaKind
    let storedFilename: String
    let originalFilename: String
    let contentType: String

    /// Creates one stable incoming item before the host app imports it.
    init(
        id: UUID = UUID(),
        kind: SharedMediaKind,
        storedFilename: String,
        originalFilename: String,
        contentType: String
    ) {
        self.id = id
        self.kind = kind
        self.storedFilename = storedFilename
        self.originalFilename = originalFilename
        self.contentType = contentType
    }
}

/// Describes one batch written atomically by the Share Extension.
struct SharedMediaIncomingManifest: Codable {
    let batchID: UUID
    let importedAt: Date
    let items: [SharedMediaIncomingItem]
}

/// Stores all persistent metadata for one shared image or video.
struct SharedMediaRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var kind: SharedMediaKind
    var relativePath: String
    var originalFilename: String
    var contentType: String
    var importedAt: Date
    var batchID: UUID
    var byteCount: Int64
    var pixelWidth: Int?
    var pixelHeight: Int?
    var duration: Double?
    var contentDigest: String
    var note: String?
    var isFavorite: Bool
    var favoriteOrder: Int?
    var lastPlaybackPosition: Double
    var playbackCount: Int

    /// Returns a compact display name while preserving the original filename.
    var displayName: String {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedNote.isEmpty ? originalFilename : trimmedNote
    }
}

/// Defines supported filters for the shared media management screen.
enum SharedMediaFilter: String, CaseIterable, Identifiable {
    case all
    case images
    case videos
    case favoriteVideos

    var id: String { rawValue }
}

/// Defines the stable shared container layout used by both app targets.
enum SharedMediaConstants {
    static let appGroupIdentifier = "group.com.ikode.MyEHViewer"
    static let incomingDirectoryName = "Incoming"
    static let manifestFilename = "manifest.json"
    static let mediaDirectoryName = "Shared Media"
    static let imagesDirectoryName = "Images"
    static let videosDirectoryName = "Videos"
}

/// Stores the portable metadata written into a shared media ZIP archive.
struct SharedMediaArchiveManifest: Codable {
    let version: Int
    let exportedAt: Date
    let records: [SharedMediaRecord]

    /// Creates the current archive schema.
    init(records: [SharedMediaRecord]) {
        version = 1
        exportedAt = Date()
        self.records = records
    }
}
