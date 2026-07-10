import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

/// Owns persistent shared images, videos, favorites, and archive transfers.
@MainActor
final class SharedMediaStore: ObservableObject {
    /// Provides an isolated store for SwiftUI previews.
    static let preview: SharedMediaStore = {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SharedMediaPreview",
            directoryHint: .isDirectory
        )
        return SharedMediaStore(
            mediaRootURL: root.appending(path: "Media", directoryHint: .isDirectory),
            metadataRootURL: root.appending(path: "Metadata", directoryHint: .isDirectory),
            incomingRootURL: root.appending(path: "Incoming", directoryHint: .isDirectory)
        )
    }()

    @Published private(set) var records: [SharedMediaRecord] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isTransferringArchive = false
    @Published private(set) var transferMessage: String?

    private let fileManager: FileManager
    private let mediaRootURL: URL
    private let metadataRootURL: URL
    private let incomingRootURL: URL
    private let indexURL: URL

    var imageRecords: [SharedMediaRecord] {
        records.filter { $0.kind == .image }.sorted { $0.importedAt > $1.importedAt }
    }

    var videoRecords: [SharedMediaRecord] {
        records.filter { $0.kind == .video }.sorted { $0.importedAt > $1.importedAt }
    }

    var favoriteImages: [SharedMediaRecord] {
        favoriteRecords(kind: .image)
    }

    var favoriteVideos: [SharedMediaRecord] {
        favoriteRecords(kind: .video)
    }

    var totalByteCount: Int64 {
        records.reduce(0) { $0 + $1.byteCount }
    }

    var totalVideoDuration: Double {
        videoRecords.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    /// Creates the shared media store with injectable roots for tests.
    init(
        fileManager: FileManager = .default,
        mediaRootURL: URL? = nil,
        metadataRootURL: URL? = nil,
        incomingRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.mediaRootURL = mediaRootURL ?? documentsURL.appending(
            path: SharedMediaConstants.mediaDirectoryName,
            directoryHint: .isDirectory
        )
        self.metadataRootURL = metadataRootURL ?? applicationSupportURL.appending(
            path: "SharedMedia",
            directoryHint: .isDirectory
        )
        if let incomingRootURL {
            self.incomingRootURL = incomingRootURL
        } else if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedMediaConstants.appGroupIdentifier
        ) {
            self.incomingRootURL = containerURL.appending(
                path: SharedMediaConstants.incomingDirectoryName,
                directoryHint: .isDirectory
            )
        } else {
            preconditionFailure("Shared media App Group container is unavailable")
        }
        indexURL = self.metadataRootURL.appending(path: "index.json")
        prepareDirectories()
        loadIndex()
    }

    /// Resolves the current local file URL for one media record.
    func fileURL(for record: SharedMediaRecord) -> URL {
        mediaRootURL.appending(path: record.relativePath)
    }

    /// Imports completed Share Extension batches and synchronizes Files changes.
    func importIncomingAndRefresh() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            try await importIncomingBatches()
            try await refreshFromDisk()
            transferMessage = nil
        } catch {
            transferMessage = error.localizedDescription
        }
    }

    /// Toggles a shared image or video's independent favorite state.
    func toggleFavorite(_ record: SharedMediaRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavorite.toggle()
        if records[index].isFavorite {
            let nextOrder = records
                .filter { $0.kind == record.kind }
                .compactMap(\.favoriteOrder)
                .max()
                .map { $0 + 1 } ?? 0
            records[index].favoriteOrder = nextOrder
        } else {
            records[index].favoriteOrder = nil
        }
        normalizeFavoriteOrder(kind: record.kind)
        saveIndex()
    }

    /// Moves one favorite within its image or video favorite collection.
    func moveFavorite(_ record: SharedMediaRecord, direction: Int) {
        guard direction != 0 else { return }
        var favorites = favoriteRecords(kind: record.kind)
        guard let index = favorites.firstIndex(where: { $0.id == record.id }) else { return }
        let target = max(0, min(favorites.count - 1, index + direction))
        guard target != index else { return }
        favorites.swapAt(index, target)
        applyFavoriteOrder(favorites)
    }

    /// Moves one favorite to the first position of its media kind.
    func moveFavoriteToFront(_ record: SharedMediaRecord) {
        var favorites = favoriteRecords(kind: record.kind)
        guard let index = favorites.firstIndex(where: { $0.id == record.id }), index > 0 else { return }
        let moved = favorites.remove(at: index)
        favorites.insert(moved, at: 0)
        applyFavoriteOrder(favorites)
    }

    /// Updates the user note shown before the original filename.
    func setNote(_ note: String?, for record: SharedMediaRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].note = trimmed?.isEmpty == false ? trimmed : nil
        saveIndex()
    }

    /// Stores the latest video position and increments completed play sessions.
    func updatePlayback(_ record: SharedMediaRecord, position: Double, completed: Bool) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].lastPlaybackPosition = max(0, position)
        if completed {
            records[index].playbackCount += 1
            records[index].lastPlaybackPosition = 0
        }
        saveIndex()
    }

    /// Deletes one persistent media file and its local metadata.
    func delete(_ record: SharedMediaRecord) {
        try? fileManager.removeItem(at: fileURL(for: record))
        records.removeAll { $0.id == record.id }
        normalizeFavoriteOrder(kind: record.kind)
        saveIndex()
    }

    /// Creates a standard ZIP archive containing media files and metadata.
    func createArchive() async throws -> URL {
        guard !isTransferringArchive else { throw SharedMediaStoreError.transferInProgress }
        isTransferringArchive = true
        defer { isTransferringArchive = false }
        let records = records
        let mediaRootURL = mediaRootURL
        let temporaryDirectory = fileManager.temporaryDirectory.appending(
            path: "SharedMediaExport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let archiveURL = temporaryDirectory.appending(path: "EHReader-SharedMedia.zip")
        let manifestURL = temporaryDirectory.appending(path: "manifest.json")
        let manifestData = try JSONEncoder.pretty.encode(SharedMediaArchiveManifest(records: records))
        try manifestData.write(to: manifestURL, options: [.atomic])

        return try await Task.detached(priority: .utility) {
            let archive = try Archive(url: archiveURL, accessMode: .create)
            try archive.addEntry(with: "manifest.json", fileURL: manifestURL)
            for record in records {
                let sourceURL = mediaRootURL.appending(path: record.relativePath)
                guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
                try archive.addEntry(with: record.relativePath, fileURL: sourceURL)
            }
            return archiveURL
        }.value
    }

    /// Imports a validated ZIP archive and merges its records into local storage.
    func importArchive(from archiveURL: URL) async throws {
        guard !isTransferringArchive else { throw SharedMediaStoreError.transferInProgress }
        isTransferringArchive = true
        defer { isTransferringArchive = false }
        let temporaryDirectory = fileManager.temporaryDirectory.appending(
            path: "SharedMediaImport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        try await Task.detached(priority: .utility) {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            for entry in archive {
                guard Self.isSafeArchivePath(entry.path) else {
                    throw SharedMediaStoreError.unsafeArchivePath
                }
                let destinationURL = temporaryDirectory.appending(path: entry.path)
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                _ = try archive.extract(entry, to: destinationURL)
            }
        }.value

        let manifestURL = temporaryDirectory.appending(path: "manifest.json")
        let manifest = try JSONDecoder().decode(
            SharedMediaArchiveManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.version == 1 else { throw SharedMediaStoreError.unsupportedArchiveVersion }

        for importedRecord in manifest.records {
            let sourceURL = temporaryDirectory.appending(path: importedRecord.relativePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if records.contains(where: { $0.contentDigest == importedRecord.contentDigest }) { continue }
            let newID = records.contains(where: { $0.id == importedRecord.id }) ? UUID() : importedRecord.id
            let destinationDirectory = directoryURL(for: importedRecord.kind)
            let destinationFilename = persistentFilename(id: newID, originalFilename: importedRecord.originalFilename)
            let destinationURL = destinationDirectory.appending(path: destinationFilename)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            var record = importedRecord
            record = SharedMediaRecord(
                id: newID,
                kind: importedRecord.kind,
                relativePath: relativePath(for: destinationURL, kind: importedRecord.kind),
                originalFilename: importedRecord.originalFilename,
                contentType: importedRecord.contentType,
                importedAt: importedRecord.importedAt,
                batchID: importedRecord.batchID,
                byteCount: importedRecord.byteCount,
                pixelWidth: importedRecord.pixelWidth,
                pixelHeight: importedRecord.pixelHeight,
                duration: importedRecord.duration,
                contentDigest: importedRecord.contentDigest,
                note: importedRecord.note,
                isFavorite: importedRecord.isFavorite,
                favoriteOrder: importedRecord.favoriteOrder,
                lastPlaybackPosition: importedRecord.lastPlaybackPosition,
                playbackCount: importedRecord.playbackCount
            )
            records.append(record)
        }
        normalizeFavoriteOrder(kind: .image)
        normalizeFavoriteOrder(kind: .video)
        saveIndex()
    }

    /// Imports every completed batch produced by the Share Extension.
    private func importIncomingBatches() async throws {
        let batchURLs = try fileManager.contentsOfDirectory(
            at: incomingRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for batchURL in batchURLs {
            let manifestURL = batchURL.appending(path: SharedMediaConstants.manifestFilename)
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            let manifest = try JSONDecoder().decode(
                SharedMediaIncomingManifest.self,
                from: Data(contentsOf: manifestURL)
            )
            for item in manifest.items {
                let sourceURL = batchURL.appending(path: item.storedFilename)
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
                let digest = try await Self.digest(for: sourceURL)
                if records.contains(where: { $0.contentDigest == digest }) {
                    continue
                }
                let destinationDirectory = directoryURL(for: item.kind)
                let destinationFilename = persistentFilename(id: item.id, originalFilename: item.originalFilename)
                let destinationURL = destinationDirectory.appending(path: destinationFilename)
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                let metadata = try await Self.metadata(for: destinationURL, kind: item.kind)
                records.append(SharedMediaRecord(
                    id: item.id,
                    kind: item.kind,
                    relativePath: relativePath(for: destinationURL, kind: item.kind),
                    originalFilename: item.originalFilename,
                    contentType: item.contentType,
                    importedAt: manifest.importedAt,
                    batchID: manifest.batchID,
                    byteCount: metadata.byteCount,
                    pixelWidth: metadata.pixelWidth,
                    pixelHeight: metadata.pixelHeight,
                    duration: metadata.duration,
                    contentDigest: digest,
                    note: nil,
                    isFavorite: false,
                    favoriteOrder: nil,
                    lastPlaybackPosition: 0,
                    playbackCount: 0
                ))
            }
            try? fileManager.removeItem(at: batchURL)
        }
        saveIndex()
    }

    /// Reconciles the metadata index with files changed through the Files app.
    private func refreshFromDisk() async throws {
        let fileEntries = try SharedMediaKind.allCases.flatMap { kind -> [(SharedMediaKind, URL)] in
            try fileManager.contentsOfDirectory(
                at: directoryURL(for: kind),
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).map { (kind, $0) }
        }
        let previousRecords = records
        let currentPaths = Set(fileEntries.map { relativePath(for: $0.1, kind: $0.0) })
        records.removeAll { !currentPaths.contains($0.relativePath) }

        for (kind, fileURL) in fileEntries {
            let path = relativePath(for: fileURL, kind: kind)
            if let index = records.firstIndex(where: { $0.relativePath == path }) {
                records[index].byteCount = fileSize(at: fileURL)
                continue
            }
            let digest = try await Self.digest(for: fileURL)
            if records.contains(where: { $0.contentDigest == digest }) { continue }
            let metadata = try await Self.metadata(for: fileURL, kind: kind)
            if var previousRecord = previousRecords.first(where: { $0.contentDigest == digest }) {
                previousRecord.kind = kind
                previousRecord.relativePath = path
                previousRecord.originalFilename = fileURL.lastPathComponent
                previousRecord.byteCount = metadata.byteCount
                previousRecord.pixelWidth = metadata.pixelWidth
                previousRecord.pixelHeight = metadata.pixelHeight
                previousRecord.duration = metadata.duration
                records.append(previousRecord)
                continue
            }
            records.append(SharedMediaRecord(
                id: UUID(),
                kind: kind,
                relativePath: path,
                originalFilename: fileURL.lastPathComponent,
                contentType: UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? "public.data",
                importedAt: (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
                batchID: UUID(),
                byteCount: metadata.byteCount,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                duration: metadata.duration,
                contentDigest: digest,
                note: nil,
                isFavorite: false,
                favoriteOrder: nil,
                lastPlaybackPosition: 0,
                playbackCount: 0
            ))
        }
        saveIndex()
    }

    /// Returns ordered favorites for one media kind.
    private func favoriteRecords(kind: SharedMediaKind) -> [SharedMediaRecord] {
        records
            .filter { $0.kind == kind && $0.isFavorite }
            .sorted {
                if $0.favoriteOrder == $1.favoriteOrder { return $0.importedAt > $1.importedAt }
                return ($0.favoriteOrder ?? .max) < ($1.favoriteOrder ?? .max)
            }
    }

    /// Applies a complete favorite order and persists it once.
    private func applyFavoriteOrder(_ orderedRecords: [SharedMediaRecord]) {
        for (order, record) in orderedRecords.enumerated() {
            guard let index = records.firstIndex(where: { $0.id == record.id }) else { continue }
            records[index].favoriteOrder = order
        }
        saveIndex()
    }

    /// Removes gaps after a favorite is deleted or unfavorited.
    private func normalizeFavoriteOrder(kind: SharedMediaKind) {
        applyFavoriteOrder(favoriteRecords(kind: kind))
    }

    /// Creates persistent media and metadata directories.
    private func prepareDirectories() {
        try? fileManager.createDirectory(at: mediaRootURL, withIntermediateDirectories: true)
        var mediaRootValues = URLResourceValues()
        mediaRootValues.isExcludedFromBackup = true
        var mutableMediaRootURL = mediaRootURL
        try? mutableMediaRootURL.setResourceValues(mediaRootValues)
        try? fileManager.createDirectory(at: metadataRootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: incomingRootURL, withIntermediateDirectories: true)
        for kind in SharedMediaKind.allCases {
            try? fileManager.createDirectory(at: directoryURL(for: kind), withIntermediateDirectories: true)
        }
    }

    /// Loads the persisted metadata index without scanning media files.
    private func loadIndex() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let storedRecords = try? JSONDecoder().decode([SharedMediaRecord].self, from: data)
        else {
            return
        }
        records = storedRecords
    }

    /// Persists the current metadata index atomically.
    private func saveIndex() {
        do {
            let data = try JSONEncoder.pretty.encode(records)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            transferMessage = error.localizedDescription
        }
    }

    /// Returns the persistent directory for one media kind.
    private func directoryURL(for kind: SharedMediaKind) -> URL {
        let name = kind == .image
            ? SharedMediaConstants.imagesDirectoryName
            : SharedMediaConstants.videosDirectoryName
        return mediaRootURL.appending(path: name, directoryHint: .isDirectory)
    }

    /// Builds a Files-friendly name that still contains a stable identifier.
    private func persistentFilename(id: UUID, originalFilename: String) -> String {
        let sanitized = originalFilename.replacingOccurrences(of: "/", with: "-")
        return "\(id.uuidString)-\(sanitized)"
    }

    /// Builds the index path relative to the shared media root.
    private func relativePath(for fileURL: URL, kind: SharedMediaKind) -> String {
        let directoryName = kind == .image
            ? SharedMediaConstants.imagesDirectoryName
            : SharedMediaConstants.videosDirectoryName
        return "\(directoryName)/\(fileURL.lastPathComponent)"
    }

    /// Reads one file size without loading media bytes.
    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// Rejects absolute and parent-traversing ZIP paths.
    nonisolated private static func isSafeArchivePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    /// Computes a streaming SHA-256 digest without loading large videos into memory.
    nonisolated private static func digest(for url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            guard let stream = InputStream(url: url) else { throw SharedMediaStoreError.unreadableFile }
            stream.open()
            defer { stream.close() }
            var hasher = SHA256()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_048_576)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1_048_576)
                if count < 0 { throw stream.streamError ?? SharedMediaStoreError.unreadableFile }
                if count == 0 { break }
                hasher.update(data: Data(bytes: buffer, count: count))
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    /// Reads image dimensions or video duration outside the main actor.
    nonisolated private static func metadata(for url: URL, kind: SharedMediaKind) async throws -> SharedMediaMetadata {
        let byteCount = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        switch kind {
        case .image:
            return await Task.detached(priority: .utility) {
                guard
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                else {
                    return SharedMediaMetadata(byteCount: byteCount, pixelWidth: nil, pixelHeight: nil, duration: nil)
                }
                return SharedMediaMetadata(
                    byteCount: byteCount,
                    pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
                    pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int,
                    duration: nil
                )
            }.value
        case .video:
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let dimensions: CGSize? = if let track = tracks.first {
                try await track.load(.naturalSize)
            } else {
                nil
            }
            return SharedMediaMetadata(
                byteCount: byteCount,
                pixelWidth: dimensions.map { Int(abs($0.width)) },
                pixelHeight: dimensions.map { Int(abs($0.height)) },
                duration: duration.seconds.isFinite ? duration.seconds : nil
            )
        }
    }
}

/// Holds media facts collected while importing a file.
private struct SharedMediaMetadata: Sendable {
    let byteCount: Int64
    let pixelWidth: Int?
    let pixelHeight: Int?
    let duration: Double?
}

/// Describes persistent shared media failures shown to the user.
enum SharedMediaStoreError: LocalizedError {
    case unreadableFile
    case unsafeArchivePath
    case unsupportedArchiveVersion
    case transferInProgress

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "无法读取分享媒体文件。"
        case .unsafeArchivePath: "ZIP 中包含不安全的文件路径。"
        case .unsupportedArchiveVersion: "该分享媒体备份版本不受支持。"
        case .transferInProgress: "已有分享媒体导入或导出任务正在进行。"
        }
    }
}

private extension JSONEncoder {
    /// Creates a stable human-readable encoder for indexes and manifests.
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
