import XCTest
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

        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.id, itemID)
        XCTAssertEqual(record.kind, .image)
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

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

private struct TestPaths {
    let root: URL
    let media: URL
    let metadata: URL
    let incoming: URL
}
