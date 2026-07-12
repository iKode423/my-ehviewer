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
    @Published private(set) var galleries: [SharedMediaGalleryRecord] = []
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

    /// Returns the existing records in one gallery's persisted order.
    func records(in gallery: SharedMediaGalleryRecord) -> [SharedMediaRecord] {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return gallery.memberIDs.compactMap { recordsByID[$0] }
    }

    /// Returns galleries containing one media record, newest first.
    func galleries(containing record: SharedMediaRecord) -> [SharedMediaGalleryRecord] {
        galleries
            .filter { $0.memberIDs.contains(record.id) }
            .sorted { $0.importedAt > $1.importedAt }
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
        galleries = galleries.compactMap { gallery in
            var updatedGallery = gallery
            updatedGallery.memberIDs.removeAll { $0 == record.id }
            guard let coverMediaID = updatedGallery.memberIDs.first else { return nil }
            if updatedGallery.coverMediaID == record.id {
                updatedGallery.coverMediaID = coverMediaID
            }
            return updatedGallery
        }
        normalizeFavoriteOrder(kind: record.kind)
        saveIndex()
    }

    /// Deletes one gallery and media files that no remaining gallery references.
    func delete(_ gallery: SharedMediaGalleryRecord) {
        galleries.removeAll { $0.id == gallery.id }
        let referencedIDs = Set(galleries.flatMap(\.memberIDs))
        let orphanIDs = Set(gallery.memberIDs).subtracting(referencedIDs)
        let orphanRecords = records.filter { orphanIDs.contains($0.id) }
        for record in orphanRecords {
            try? fileManager.removeItem(at: fileURL(for: record))
        }
        records.removeAll { orphanIDs.contains($0.id) }
        normalizeFavoriteOrder(kind: .image)
        normalizeFavoriteOrder(kind: .video)
        saveIndex()
    }

    /// Imports one selected folder as an ordered local gallery.
    func importFolder(from folderURL: URL) async throws {
        guard !isTransferringArchive else { throw SharedMediaStoreError.transferInProgress }
        isTransferringArchive = true
        defer { isTransferringArchive = false }

        let batchID = UUID()
        let batchURL = incomingRootURL.appending(
            path: batchID.uuidString,
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: batchURL) }
        try await Self.stageFolderImport(
            from: folderURL,
            to: batchURL,
            batchID: batchID,
            importedAt: Date()
        )
        try await importIncomingBatch(at: batchURL)
        saveIndex()
        transferMessage = nil
    }

    /// Creates a standard ZIP archive containing media files and metadata.
    func createArchive() async throws -> URL {
        guard !isTransferringArchive else { throw SharedMediaStoreError.transferInProgress }
        isTransferringArchive = true
        defer { isTransferringArchive = false }
        let records = records
        let galleries = galleries
        let mediaRootURL = mediaRootURL
        let temporaryDirectory = fileManager.temporaryDirectory.appending(
            path: "SharedMediaExport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let archiveURL = temporaryDirectory.appending(path: "EHReader-SharedMedia.zip")
        let manifestURL = temporaryDirectory.appending(path: "manifest.json")
        let manifestData = try JSONEncoder.pretty.encode(
            SharedMediaArchiveManifest(records: records, galleries: galleries)
        )
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
        guard manifest.version == 1 || manifest.version == 2 else {
            throw SharedMediaStoreError.unsupportedArchiveVersion
        }

        var importedMediaIDs: [UUID: UUID] = [:]
        for importedRecord in manifest.records {
            guard Self.isSafeArchivePath(importedRecord.relativePath) else {
                throw SharedMediaStoreError.unsafeArchivePath
            }
            let sourceURL = temporaryDirectory
                .appending(path: importedRecord.relativePath)
                .standardizedFileURL
            guard Self.contains(sourceURL, in: temporaryDirectory) else {
                throw SharedMediaStoreError.unsafeArchivePath
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if let existingRecord = records.first(where: { $0.contentDigest == importedRecord.contentDigest }) {
                importedMediaIDs[importedRecord.id] = existingRecord.id
                continue
            }
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
            importedMediaIDs[importedRecord.id] = newID
        }
        if manifest.version == 2 {
            for importedGallery in manifest.galleries {
                let memberIDs = Self.uniqueIDs(
                    importedGallery.memberIDs.compactMap { importedMediaIDs[$0] }
                )
                guard let coverMediaID = memberIDs.first else { continue }
                let galleryID = galleries.contains(where: { $0.id == importedGallery.id })
                    ? UUID()
                    : importedGallery.id
                let importedCoverMediaID = importedMediaIDs[importedGallery.coverMediaID]
                galleries.append(SharedMediaGalleryRecord(
                    id: galleryID,
                    title: importedGallery.title,
                    importedAt: importedGallery.importedAt,
                    coverMediaID: importedCoverMediaID.map { memberIDs.contains($0) ? $0 : coverMediaID }
                        ?? coverMediaID,
                    memberIDs: memberIDs
                ))
            }
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
            try await importIncomingBatch(at: batchURL)
        }
        saveIndex()
    }

    /// Imports one completed incoming batch without scanning unrelated batches.
    private func importIncomingBatch(at batchURL: URL) async throws {
        let manifestURL = batchURL.appending(path: SharedMediaConstants.manifestFilename)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        let manifest = try JSONDecoder().decode(
            SharedMediaIncomingManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        var importedMediaIDs: [UUID: UUID] = [:]
        for item in manifest.items {
            guard Self.isSafeRelativePath(item.storedFilename) else {
                throw SharedMediaStoreError.unsafeIncomingPath
            }
            let sourceURL = batchURL.appending(path: item.storedFilename).standardizedFileURL
            guard Self.contains(sourceURL, in: batchURL) else {
                throw SharedMediaStoreError.unsafeIncomingPath
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let digest = try await Self.digest(for: sourceURL)
            if let existingRecord = records.first(where: { $0.contentDigest == digest }) {
                importedMediaIDs[item.id] = existingRecord.id
                continue
            }
            let metadata = try await Self.metadata(for: sourceURL, kind: item.kind)
            let destinationDirectory = directoryURL(for: item.kind)
            let recordID = records.contains(where: { $0.id == item.id }) ? UUID() : item.id
            let destinationFilename = persistentFilename(id: recordID, originalFilename: item.originalFilename)
            let destinationURL = destinationDirectory.appending(path: destinationFilename)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            records.append(SharedMediaRecord(
                id: recordID,
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
            importedMediaIDs[item.id] = recordID
        }
        if let incomingGallery = manifest.gallery {
            let memberIDs = Self.uniqueIDs(
                incomingGallery.memberIDs.compactMap { importedMediaIDs[$0] }
            )
            if let coverMediaID = memberIDs.first {
                let galleryID = galleries.contains(where: { $0.id == incomingGallery.id })
                    ? UUID()
                    : incomingGallery.id
                galleries.append(SharedMediaGalleryRecord(
                    id: galleryID,
                    title: incomingGallery.title,
                    importedAt: manifest.importedAt,
                    coverMediaID: coverMediaID,
                    memberIDs: memberIDs
                ))
            }
        }
        try? fileManager.removeItem(at: batchURL)
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
        reconcileGalleries()
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
        var updatedRecords = records
        for (order, record) in orderedRecords.enumerated() {
            guard let index = updatedRecords.firstIndex(where: { $0.id == record.id }) else { continue }
            updatedRecords[index].favoriteOrder = order
        }
        records = updatedRecords
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
        guard let data = try? Data(contentsOf: indexURL) else { return }
        if let index = try? JSONDecoder().decode(SharedMediaIndex.self, from: data) {
            records = index.records
            galleries = index.galleries
            reconcileGalleries()
            return
        }
        if let storedRecords = try? JSONDecoder().decode([SharedMediaRecord].self, from: data) {
            records = storedRecords
            galleries = []
        }
    }

    /// Persists the current metadata index atomically.
    private func saveIndex() {
        do {
            let data = try JSONEncoder.pretty.encode(
                SharedMediaIndex(records: records, galleries: galleries)
            )
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            transferMessage = error.localizedDescription
        }
    }

    /// Removes missing members and empty galleries after external file changes.
    private func reconcileGalleries() {
        let recordIDs = Set(records.map(\.id))
        galleries = galleries.compactMap { gallery in
            var updatedGallery = gallery
            updatedGallery.memberIDs = Self.uniqueIDs(
                gallery.memberIDs.filter { recordIDs.contains($0) }
            )
            guard let firstMemberID = updatedGallery.memberIDs.first else { return nil }
            if !recordIDs.contains(updatedGallery.coverMediaID) {
                updatedGallery.coverMediaID = firstMemberID
            }
            return updatedGallery
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

    /// Copies a selected folder into one complete incoming batch off the main actor.
    nonisolated private static func stageFolderImport(
        from folderURL: URL,
        to batchURL: URL,
        batchID: UUID,
        importedAt: Date
    ) async throws {
        try await Task.detached(priority: .utility) {
            let candidates = try folderCandidates(in: folderURL)
            guard !candidates.isEmpty else {
                throw SharedMediaStoreError.noSupportedFolderMedia
            }
            try FileManager.default.createDirectory(
                at: batchURL,
                withIntermediateDirectories: true
            )
            var items: [SharedMediaIncomingItem] = []
            for candidate in candidates {
                let itemID = UUID()
                let pathExtension = candidate.url.pathExtension
                let storedFilename = pathExtension.isEmpty
                    ? itemID.uuidString
                    : "\(itemID.uuidString).\(pathExtension)"
                try FileManager.default.copyItem(
                    at: candidate.url,
                    to: batchURL.appending(path: storedFilename)
                )
                items.append(SharedMediaIncomingItem(
                    id: itemID,
                    kind: candidate.kind,
                    storedFilename: storedFilename,
                    originalFilename: candidate.relativePath,
                    contentType: candidate.contentType.identifier
                ))
            }
            let title = folderURL.lastPathComponent.isEmpty
                ? "本地图库"
                : folderURL.lastPathComponent
            let manifest = SharedMediaIncomingManifest(
                batchID: batchID,
                importedAt: importedAt,
                items: items,
                gallery: SharedMediaIncomingGallery(
                    title: title,
                    memberIDs: items.map(\.id)
                )
            )
            try JSONEncoder().encode(manifest).write(
                to: batchURL.appending(path: SharedMediaConstants.manifestFilename),
                options: [.atomic]
            )
        }.value
    }

    /// Recursively finds supported media in natural relative-path order.
    nonisolated private static func folderCandidates(
        in folderURL: URL
    ) throws -> [SharedMediaFolderCandidate] {
        let fileManager = FileManager.default
        let rootURL = folderURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isDirectory(rootURL) else { throw SharedMediaStoreError.unreadableFile }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw SharedMediaStoreError.unreadableFile
        }

        var candidates: [SharedMediaFolderCandidate] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ]) else {
                enumerator.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory != true else { continue }
            let resolvedURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            guard contains(resolvedURL, in: rootURL) else { continue }
            let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: fileURL.pathExtension)
            guard let contentType else {
                continue
            }
            let kind: SharedMediaKind
            if contentType.conforms(to: .image) {
                kind = .image
            } else if contentType.conforms(to: .movie) {
                kind = .video
            } else {
                continue
            }
            let relativePath = resolvedURL.pathComponents
                .dropFirst(rootURL.pathComponents.count)
                .joined(separator: "/")
            guard !relativePath.isEmpty else { continue }
            candidates.append(SharedMediaFolderCandidate(
                url: resolvedURL,
                relativePath: relativePath,
                kind: kind,
                contentType: contentType
            ))
        }
        return candidates.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    /// Checks both file-system and provider metadata for a directory.
    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Rejects absolute and parent-traversing ZIP paths.
    nonisolated private static func isSafeArchivePath(_ path: String) -> Bool {
        isSafeRelativePath(path)
    }

    /// Rejects absolute, empty, and parent-traversing relative paths.
    nonisolated private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    /// Confirms a standardized URL remains below an expected directory.
    nonisolated private static func contains(_ childURL: URL, in directoryURL: URL) -> Bool {
        let directoryComponents = directoryURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents
        let childComponents = childURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents
        return childComponents.count > directoryComponents.count
            && childComponents.starts(with: directoryComponents)
    }

    /// Removes repeated identifiers while preserving their first position.
    nonisolated private static func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
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
    case noSupportedFolderMedia
    case unsafeIncomingPath
    case unsafeArchivePath
    case unsupportedArchiveVersion
    case transferInProgress

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "无法读取分享媒体文件。"
        case .noSupportedFolderMedia: "所选文件夹中没有可导入的图片或视频。"
        case .unsafeIncomingPath: "分享文件夹中包含不安全的文件路径。"
        case .unsafeArchivePath: "ZIP 中包含不安全的文件路径。"
        case .unsupportedArchiveVersion: "该分享媒体备份版本不受支持。"
        case .transferInProgress: "已有分享媒体导入或导出任务正在进行。"
        }
    }
}

/// Holds one supported file discovered inside a selected folder.
private struct SharedMediaFolderCandidate {
    let url: URL
    let relativePath: String
    let kind: SharedMediaKind
    let contentType: UTType
}

private extension JSONEncoder {
    /// Creates a stable human-readable encoder for indexes and manifests.
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
