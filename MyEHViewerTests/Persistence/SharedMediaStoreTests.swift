import XCTest
import ZIPFoundation
@testable import MyEHViewer

@MainActor
final class SharedMediaStoreTests: XCTestCase {
    /// Confirms incoming image batches become persistent Files-visible records.
    func testImportIncomingImageCreatesPersistentRecord() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let itemID = UUID()
        try writeIncomingImage(paths: paths, itemID: itemID, batchID: UUID())
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )

        await store.importIncomingAndRefresh()

        XCTAssertNil(store.transferMessage)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.id, itemID)
        XCTAssertEqual(record.kind, .image)
        XCTAssertEqual(store.galleries.count, 1)
        XCTAssertEqual(store.galleries.first?.memberIDs, [record.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: record).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.incoming.path), [])
    }

    /// Confirms content hashing prevents duplicate shared files from consuming space twice.
    func testImportIncomingSkipsDuplicateContent() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeIncomingImage(paths: paths, itemID: UUID(), batchID: UUID())
        try writeIncomingImage(paths: paths, itemID: UUID(), batchID: UUID())
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )

        await store.importIncomingAndRefresh()

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.galleries.count, 2)
    }

    /// Confirms a folder manifest creates one gallery with persisted member order.
    func testImportIncomingFolderCreatesOrderedGallery() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeIncomingGallery(
            paths: paths,
            title: "Sample Folder",
            entries: [
                ("chapter/2.png", Data("two".utf8)),
                ("chapter/10.png", Data("ten".utf8))
            ]
        )
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )

        await store.importIncomingAndRefresh()

        XCTAssertNil(store.transferMessage)
        let gallery = try XCTUnwrap(store.galleries.first)
        XCTAssertEqual(gallery.title, "Sample Folder")
        XCTAssertEqual(
            store.records(in: gallery).map(\.originalFilename),
            ["chapter/2.png", "chapter/10.png"]
        )
        XCTAssertEqual(gallery.coverMediaID, gallery.memberIDs.first)
    }

    /// Confirms a selected folder becomes one naturally ordered local gallery.
    func testImportFolderCreatesOrderedGalleryAndFiltersUnsupportedEntries() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let sourceURL = paths.root.appending(
            path: "Selected Folder",
            directoryHint: .isDirectory
        )
        let chapterURL = sourceURL.appending(path: "chapter", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chapterURL, withIntermediateDirectories: true)
        var tenPNG = Self.pngData
        var twoPNG = Self.pngData
        tenPNG.append(10)
        twoPNG.append(2)
        try tenPNG.write(to: chapterURL.appending(path: "10.png"))
        try twoPNG.write(to: chapterURL.appending(path: "2.png"))
        try Self.pngData.write(to: sourceURL.appending(path: ".hidden.png"))
        try Data("notes".utf8).write(to: sourceURL.appending(path: "notes.txt"))
        try FileManager.default.createSymbolicLink(
            at: chapterURL.appending(path: "linked.png"),
            withDestinationURL: chapterURL.appending(path: "2.png")
        )
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )

        try await store.importFolder(from: sourceURL)

        let gallery = try XCTUnwrap(store.galleries.first)
        XCTAssertEqual(gallery.title, "Selected Folder")
        XCTAssertEqual(
            store.records(in: gallery).map(\.originalFilename),
            ["chapter/2.png", "chapter/10.png"]
        )
        XCTAssertEqual(store.records.count, 2)
        XCTAssertTrue(store.records.allSatisfy {
            FileManager.default.fileExists(atPath: store.fileURL(for: $0).path)
        })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.incoming.path), [])
    }

    /// Confirms a folder without supported media does not create an empty gallery.
    func testImportFolderRejectsFolderWithoutSupportedMedia() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let sourceURL = paths.root.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: sourceURL.appending(path: "notes.txt"))
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )

        do {
            try await store.importFolder(from: sourceURL)
            XCTFail("Expected unsupported folder rejection")
        } catch SharedMediaStoreError.noSupportedFolderMedia {
            XCTAssertTrue(store.records.isEmpty)
            XCTAssertTrue(store.galleries.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.incoming.path), [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Confirms duplicate bytes can belong to two galleries and delete by final reference.
    func testDeleteGalleryPreservesSharedMediaUntilLastReference() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let sharedData = Data("shared-image".utf8)
        try writeIncomingGallery(paths: paths, title: "First", entries: [("1.png", sharedData)])
        try writeIncomingGallery(paths: paths, title: "Second", entries: [("1.png", sharedData)])
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )
        await store.importIncomingAndRefresh()

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.galleries.count, 2)
        let record = try XCTUnwrap(store.records.first)
        let fileURL = store.fileURL(for: record)

        store.delete(store.galleries[0])

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.galleries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.delete(store.galleries[0])

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.galleries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// Confirms Files renames preserve favorite and metadata identity through digest matching.
    func testFilesRenamePreservesFavoriteState() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try writeIncomingImage(paths: paths, itemID: UUID(), batchID: UUID())
        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )
        await store.importIncomingAndRefresh()
        let originalRecord = try XCTUnwrap(store.records.first)
        store.toggleFavorite(originalRecord)
        let renamedURL = store.fileURL(for: originalRecord)
            .deletingLastPathComponent()
            .appending(path: "renamed-from-files.png")
        try FileManager.default.moveItem(at: store.fileURL(for: originalRecord), to: renamedURL)

        await store.importIncomingAndRefresh()

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.id, originalRecord.id)
        XCTAssertEqual(store.favoriteImages.count, 1)
        XCTAssertEqual(store.records.first?.relativePath, "Images/renamed-from-files.png")
    }

    /// Confirms favorite state and ZIP archives survive a complete store migration.
    func testArchiveRoundTripPreservesFavoriteImage() async throws {
        let sourcePaths = try makePaths()
        let restoredPaths = try makePaths()
        defer {
            try? FileManager.default.removeItem(at: sourcePaths.root)
            try? FileManager.default.removeItem(at: restoredPaths.root)
        }
        try writeIncomingImage(paths: sourcePaths, itemID: UUID(), batchID: UUID())
        let sourceStore = SharedMediaStore(
            mediaRootURL: sourcePaths.media,
            metadataRootURL: sourcePaths.metadata,
            incomingRootURL: sourcePaths.incoming
        )
        await sourceStore.importIncomingAndRefresh()
        let sourceRecord = try XCTUnwrap(sourceStore.records.first)
        sourceStore.toggleFavorite(sourceRecord)
        let archiveURL = try await sourceStore.createArchive()

        let restoredStore = SharedMediaStore(
            mediaRootURL: restoredPaths.media,
            metadataRootURL: restoredPaths.metadata,
            incomingRootURL: restoredPaths.incoming
        )
        try await restoredStore.importArchive(from: archiveURL)

        XCTAssertEqual(restoredStore.records.count, 1)
        XCTAssertEqual(restoredStore.favoriteImages.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredStore.fileURL(for: restoredStore.records[0]).path))
    }

    /// Confirms a v2 archive restores gallery metadata and ordered relationships.
    func testArchiveRoundTripPreservesGallery() async throws {
        let sourcePaths = try makePaths()
        let restoredPaths = try makePaths()
        defer {
            try? FileManager.default.removeItem(at: sourcePaths.root)
            try? FileManager.default.removeItem(at: restoredPaths.root)
        }
        try writeIncomingGallery(
            paths: sourcePaths,
            title: "Archive Gallery",
            entries: [
                ("2.png", Data("two".utf8)),
                ("10.png", Data("ten".utf8))
            ]
        )
        let sourceStore = SharedMediaStore(
            mediaRootURL: sourcePaths.media,
            metadataRootURL: sourcePaths.metadata,
            incomingRootURL: sourcePaths.incoming
        )
        await sourceStore.importIncomingAndRefresh()
        let sourceGallery = try XCTUnwrap(sourceStore.galleries.first)
        sourceStore.setNote("归档备注", for: sourceGallery)
        let archiveURL = try await sourceStore.createArchive()

        let restoredStore = SharedMediaStore(
            mediaRootURL: restoredPaths.media,
            metadataRootURL: restoredPaths.metadata,
            incomingRootURL: restoredPaths.incoming
        )
        try await restoredStore.importArchive(from: archiveURL)

        let gallery = try XCTUnwrap(restoredStore.galleries.first)
        XCTAssertEqual(gallery.title, "Archive Gallery")
        XCTAssertEqual(gallery.note, "归档备注")
        XCTAssertEqual(
            restoredStore.records(in: gallery).map(\.originalFilename),
            ["2.png", "10.png"]
        )
    }

    /// Confirms the versioned index still loads the legacy record-array format.
    func testLegacyIndexStillLoads() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try FileManager.default.createDirectory(at: paths.metadata, withIntermediateDirectories: true)
        let record = makeRecord(id: UUID(), digest: "legacy")
        try JSONEncoder().encode([record]).write(to: paths.metadata.appending(path: "index.json"))

        let store = SharedMediaStore(
            mediaRootURL: paths.media,
            metadataRootURL: paths.metadata,
            incomingRootURL: paths.incoming
        )

        XCTAssertEqual(store.records.map(\.id), [record.id])
        XCTAssertEqual(store.galleries.count, 1)
        XCTAssertEqual(store.galleries.first?.memberIDs, [record.id])
    }

    /// Confirms a legacy v1 archive imports media into a migrated batch gallery.
    func testLegacyArchiveStillImports() async throws {
        let archivePaths = try makePaths()
        let restoredPaths = try makePaths()
        defer {
            try? FileManager.default.removeItem(at: archivePaths.root)
            try? FileManager.default.removeItem(at: restoredPaths.root)
        }
        let record = makeRecord(id: UUID(), digest: "legacy-archive")
        let archiveURL = try makeLegacyArchive(paths: archivePaths, record: record)
        let store = SharedMediaStore(
            mediaRootURL: restoredPaths.media,
            metadataRootURL: restoredPaths.metadata,
            incomingRootURL: restoredPaths.incoming
        )

        try await store.importArchive(from: archiveURL)

        XCTAssertEqual(store.records.map(\.id), [record.id])
        XCTAssertEqual(store.galleries.count, 1)
        XCTAssertEqual(store.galleries.first?.memberIDs, [record.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: store.records[0]).path))
    }

    /// Confirms manifest paths cannot escape the extracted archive directory.
    func testArchiveRejectsUnsafeManifestRecordPath() async throws {
        let archivePaths = try makePaths()
        let restoredPaths = try makePaths()
        defer {
            try? FileManager.default.removeItem(at: archivePaths.root)
            try? FileManager.default.removeItem(at: restoredPaths.root)
        }
        var record = makeRecord(id: UUID(), digest: "unsafe")
        record.relativePath = "../escape.png"
        let archiveURL = try makeLegacyArchive(paths: archivePaths, record: record, includesMedia: false)
        let store = SharedMediaStore(
            mediaRootURL: restoredPaths.media,
            metadataRootURL: restoredPaths.metadata,
            incomingRootURL: restoredPaths.incoming
        )

        do {
            try await store.importArchive(from: archiveURL)
            XCTFail("Expected unsafe archive path rejection")
        } catch SharedMediaStoreError.unsafeArchivePath {
            XCTAssertTrue(store.records.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Creates isolated media, metadata, and incoming directories.
    private func makePaths() throws -> TestPaths {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SharedMediaStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let paths = TestPaths(
            root: root,
            media: root.appending(path: "Media", directoryHint: .isDirectory),
            metadata: root.appending(path: "Metadata", directoryHint: .isDirectory),
            incoming: root.appending(path: "Incoming", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(at: paths.incoming, withIntermediateDirectories: true)
        return paths
    }

    /// Writes one completed one-pixel PNG Share Extension batch.
    private func writeIncomingImage(paths: TestPaths, itemID: UUID, batchID: UUID) throws {
        let batchURL = paths.incoming.appending(path: batchID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: batchURL, withIntermediateDirectories: true)
        let filename = "\(itemID.uuidString).png"
        try Self.pngData.write(to: batchURL.appending(path: filename))
        let manifest = SharedMediaIncomingManifest(
            batchID: batchID,
            importedAt: Date(),
            items: [
                SharedMediaIncomingItem(
                    id: itemID,
                    kind: .image,
                    storedFilename: filename,
                    originalFilename: "sample.png",
                    contentType: "public.png"
                )
            ]
        )
        try JSONEncoder().encode(manifest).write(
            to: batchURL.appending(path: SharedMediaConstants.manifestFilename)
        )
    }

    /// Writes one completed folder-gallery batch with explicit member order.
    private func writeIncomingGallery(
        paths: TestPaths,
        title: String,
        entries: [(relativePath: String, data: Data)]
    ) throws {
        let batchID = UUID()
        let batchURL = paths.incoming.appending(path: batchID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: batchURL, withIntermediateDirectories: true)
        var items: [SharedMediaIncomingItem] = []
        for entry in entries {
            let itemID = UUID()
            let storedFilename = "\(itemID.uuidString).png"
            try entry.data.write(to: batchURL.appending(path: storedFilename))
            items.append(SharedMediaIncomingItem(
                id: itemID,
                kind: .image,
                storedFilename: storedFilename,
                originalFilename: entry.relativePath,
                contentType: "public.png"
            ))
        }
        let manifest = SharedMediaIncomingManifest(
            batchID: batchID,
            importedAt: Date(),
            items: items,
            gallery: SharedMediaIncomingGallery(title: title, memberIDs: items.map(\.id))
        )
        try JSONEncoder().encode(manifest).write(
            to: batchURL.appending(path: SharedMediaConstants.manifestFilename)
        )
    }

    /// Creates one legacy-compatible record for index decoding tests.
    private func makeRecord(id: UUID, digest: String) -> SharedMediaRecord {
        SharedMediaRecord(
            id: id,
            kind: .image,
            relativePath: "Images/\(id.uuidString).png",
            originalFilename: "sample.png",
            contentType: "public.png",
            importedAt: Date(),
            batchID: UUID(),
            byteCount: 1,
            pixelWidth: 1,
            pixelHeight: 1,
            duration: nil,
            contentDigest: digest,
            note: nil,
            isFavorite: false,
            favoriteOrder: nil,
            lastPlaybackPosition: 0,
            playbackCount: 0
        )
    }

    /// Creates one portable v1 ZIP fixture using the legacy manifest shape.
    private func makeLegacyArchive(
        paths: TestPaths,
        record: SharedMediaRecord,
        includesMedia: Bool = true
    ) throws -> URL {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let sourceURL = paths.root.appending(path: record.relativePath)
        if includesMedia {
            try FileManager.default.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.pngData.write(to: sourceURL)
        }
        let manifestURL = paths.root.appending(path: "manifest.json")
        try JSONEncoder().encode(LegacyArchiveManifest(records: [record])).write(to: manifestURL)
        let archiveURL = paths.root.appending(path: "legacy.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "manifest.json", fileURL: manifestURL)
        if includesMedia {
            try archive.addEntry(with: record.relativePath, fileURL: sourceURL)
        }
        return archiveURL
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

/// Reproduces the archive manifest written before gallery support.
private struct LegacyArchiveManifest: Codable {
    let version = 1
    let exportedAt = Date()
    let records: [SharedMediaRecord]
}

private struct TestPaths {
    let root: URL
    let media: URL
    let metadata: URL
    let incoming: URL
}
