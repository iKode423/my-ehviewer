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

/// Describes one ordered gallery produced from a shared folder.
struct SharedMediaIncomingGallery: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let memberIDs: [UUID]

    /// Creates one incoming folder gallery with stable member order.
    init(id: UUID = UUID(), title: String, memberIDs: [UUID]) {
        self.id = id
        self.title = title
        self.memberIDs = memberIDs
    }
}

/// Describes one batch written atomically by the Share Extension.
struct SharedMediaIncomingManifest: Codable {
    let batchID: UUID
    let importedAt: Date
    let items: [SharedMediaIncomingItem]
    let gallery: SharedMediaIncomingGallery?

    /// Creates a media batch with an optional shared-folder gallery.
    init(
        batchID: UUID,
        importedAt: Date,
        items: [SharedMediaIncomingItem],
        gallery: SharedMediaIncomingGallery? = nil
    ) {
        self.batchID = batchID
        self.importedAt = importedAt
        self.items = items
        self.gallery = gallery
    }
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

/// Stores one local gallery and its ordered media relationships.
struct SharedMediaGalleryRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var importedAt: Date
    var coverMediaID: UUID
    var memberIDs: [UUID]
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

/// Stores the versioned shared media index used by the host app.
struct SharedMediaIndex: Codable {
    let version: Int
    let records: [SharedMediaRecord]
    let galleries: [SharedMediaGalleryRecord]

    /// Creates the current persistent index schema.
    init(records: [SharedMediaRecord], galleries: [SharedMediaGalleryRecord]) {
        version = 2
        self.records = records
        self.galleries = galleries
    }
}

/// Stores the portable metadata written into a shared media ZIP archive.
struct SharedMediaArchiveManifest: Codable {
    let version: Int
    let exportedAt: Date
    let records: [SharedMediaRecord]
    let galleries: [SharedMediaGalleryRecord]

    /// Creates the current archive schema.
    init(records: [SharedMediaRecord], galleries: [SharedMediaGalleryRecord]) {
        version = 2
        exportedAt = Date()
        self.records = records
        self.galleries = galleries
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case records
        case galleries
    }

    /// Decodes both legacy v1 archives and current v2 archives.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        records = try container.decode([SharedMediaRecord].self, forKey: .records)
        galleries = try container.decodeIfPresent([SharedMediaGalleryRecord].self, forKey: .galleries) ?? []
    }
}
