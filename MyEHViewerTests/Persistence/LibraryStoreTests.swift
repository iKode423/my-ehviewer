import XCTest
@testable import MyEHViewer

/// Verifies local library persistence for history, favorites, and progress.
@MainActor
final class LibraryStoreTests: XCTestCase {
    /// Confirms recorded galleries and favorite state persist across store instances.
    func testRecordAndFavoritePersist() {
        let userDefaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: userDefaults, storageKey: "library-test")
        let detail = makeDetail()
        let fallback = makeSearchResult()

        store.record(detail: detail, fallback: fallback)
        store.toggleFavorite(detail: detail, fallback: fallback)

        let restored = LibraryStore(userDefaults: userDefaults, storageKey: "library-test")

        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.favorites.count, 1)
        XCTAssertTrue(restored.isFavorite(detail.identifier))
        XCTAssertNotNil(restored.record(for: detail.identifier))
        XCTAssertEqual(restored.history.first?.title, "Sample Gallery")
    }

    /// Confirms reader progress updates the existing history record.
    func testUpdateProgressPersistsLastReadPage() {
        let userDefaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: userDefaults, storageKey: "library-progress-test")
        let detail = makeDetail()
        store.record(detail: detail, fallback: makeSearchResult())

        store.updateProgress(
            imagePage: EHImagePage(
                galleryID: 100,
                pageNumber: 2,
                pageURL: URL(string: "https://e-hentai.org/s/ddddeeeeff/100-2")!,
                title: "Sample Gallery - 2",
                imageURL: URL(string: "https://example.test/2.webp")!,
                previousPageURL: URL(string: "https://e-hentai.org/s/aaaabbbbcc/100-1")!,
                nextPageURL: nil,
                galleryURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!,
                originalImageURL: nil
            )
        )

        let restored = LibraryStore(userDefaults: userDefaults, storageKey: "library-progress-test")

        XCTAssertEqual(restored.history.first?.lastReadPage, 2)
        XCTAssertEqual(restored.history.first?.lastReadPageURL?.absoluteString, "https://e-hentai.org/s/ddddeeeeff/100-2")
    }

    /// Confirms reader progress creates a history record when detail was not opened first.
    func testUpdateProgressCreatesHistoryRecord() {
        let userDefaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: userDefaults, storageKey: "library-progress-create-test")

        store.updateProgress(
            imagePage: EHImagePage(
                galleryID: 100,
                pageNumber: 27,
                pageURL: URL(string: "https://e-hentai.org/s/zzzzxxxxcc/100-27")!,
                title: "Sample Gallery - 27",
                imageURL: URL(string: "https://example.test/27.webp")!,
                previousPageURL: nil,
                nextPageURL: nil,
                galleryURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!,
                originalImageURL: nil
            )
        )

        let restored = LibraryStore(userDefaults: userDefaults, storageKey: "library-progress-create-test")

        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.history.first?.lastReadPage, 27)
        XCTAssertEqual(restored.history.first?.pageCount, nil)
    }

    /// Confirms image favorites persist and can be manually reordered.
    func testImageFavoritesPersistAndMove() {
        let userDefaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: userDefaults, storageKey: "library-image-favorite-test")
        let firstPage = makeImagePage(pageNumber: 1)
        let secondPage = makeImagePage(pageNumber: 2)
        let thirdPage = makeImagePage(pageNumber: 3)

        store.toggleImageFavorite(imagePage: firstPage)
        store.toggleImageFavorite(imagePage: secondPage)
        store.toggleImageFavorite(imagePage: thirdPage)
        guard
            let secondFavorite = store.imageFavorites.first(where: { $0.pageNumber == 2 }),
            let thirdFavorite = store.imageFavorites.first(where: { $0.pageNumber == 3 })
        else {
            XCTFail("Expected image favorites to be stored")
            return
        }
        store.moveImageFavorite(secondFavorite, direction: -1)
        store.moveImageFavoriteToFront(thirdFavorite)

        let restored = LibraryStore(userDefaults: userDefaults, storageKey: "library-image-favorite-test")

        XCTAssertEqual(restored.imageFavorites.map(\.pageNumber), [3, 2, 1])
        XCTAssertTrue(restored.isImageFavorite(firstPage))
        XCTAssertTrue(restored.isImageFavorite(secondPage))
        XCTAssertTrue(restored.isImageFavorite(thirdPage))
    }

    /// Confirms local state can be fully removed from persistence.
    func testRemoveAllClearsPersistedState() {
        let userDefaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: userDefaults, storageKey: "library-remove-test")
        let detail = makeDetail()

        store.record(detail: detail, fallback: makeSearchResult())
        store.toggleFavorite(detail: detail, fallback: makeSearchResult())
        store.removeAll()

        let restored = LibraryStore(userDefaults: userDefaults, storageKey: "library-remove-test")

        XCTAssertTrue(restored.history.isEmpty)
        XCTAssertTrue(restored.favorites.isEmpty)
    }

    /// Confirms local records and cleanup are scoped by content site.
    func testRecordsAndRemovalAreScopedBySite() {
        let userDefaults = makeUserDefaults()
        let store = LibraryStore(userDefaults: userDefaults, storageKey: "library-site-test")
        let ehDetail = makeDetail()
        let hitomiDetail = makeDetail(
            identifier: EHGalleryIdentifier(gid: 4037854, token: "hitomi", site: .hitomi),
            title: "Hitomi Gallery"
        )

        store.toggleFavorite(detail: ehDetail, fallback: makeSearchResult())
        store.toggleFavorite(detail: hitomiDetail, fallback: makeSearchResult(identifier: hitomiDetail.identifier, pageURL: hitomiDetail.identifier.url()))

        XCTAssertEqual(store.favorites(for: .eHentai).map(\.identifier), [ehDetail.identifier])
        XCTAssertEqual(store.favorites(for: .hitomi).map(\.identifier), [hitomiDetail.identifier])

        store.removeAll(for: .hitomi)

        XCTAssertEqual(store.history(for: .eHentai).map(\.identifier), [ehDetail.identifier])
        XCTAssertTrue(store.history(for: .hitomi).isEmpty)
        XCTAssertTrue(store.isFavorite(ehDetail.identifier))
        XCTAssertFalse(store.isFavorite(hitomiDetail.identifier))
    }

    /// Creates isolated defaults for each test run.
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MyEHViewerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Creates a neutral reader image page fixture.
    private func makeImagePage(pageNumber: Int) -> EHImagePage {
        EHImagePage(
            galleryID: 100,
            pageNumber: pageNumber,
            pageURL: URL(string: "https://e-hentai.org/s/page-token/100-\(pageNumber)")!,
            title: "Sample Gallery",
            imageURL: URL(string: "https://example.test/\(pageNumber).webp")!,
            previousPageURL: nil,
            nextPageURL: nil,
            galleryURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!,
            originalImageURL: nil
        )
    }

    /// Creates a neutral gallery detail fixture.
    private func makeDetail(
        identifier: EHGalleryIdentifier = EHGalleryIdentifier(gid: 100, token: "abcdef1234"),
        title: String = "Sample Gallery"
    ) -> EHGalleryDetail {
        EHGalleryDetail(
            identifier: identifier,
            title: title,
            japaneseTitle: nil,
            category: "Manga",
            coverURL: URL(string: "https://example.test/cover.jpg"),
            uploader: "demo",
            metadata: [EHMetadataItem(key: "Length:", value: "2 pages")],
            ratingLabel: nil,
            ratingCount: nil,
            tags: [],
            pageLinks: [],
            thumbnailPageURLs: [],
            pageCount: 2
        )
    }

    /// Creates a neutral search result fixture.
    private func makeSearchResult() -> EHSearchResult {
        makeSearchResult(
            identifier: EHGalleryIdentifier(gid: 100, token: "abcdef1234"),
            pageURL: URL(string: "https://e-hentai.org/g/100/abcdef1234/")!
        )
    }

    /// Creates a neutral search result fixture for one site.
    private func makeSearchResult(identifier: EHGalleryIdentifier, pageURL: URL) -> EHSearchResult {
        EHSearchResult(
            identifier: identifier,
            title: "Fallback Gallery",
            category: "Manga",
            pageURL: pageURL,
            thumbnailURL: nil,
            uploader: "demo",
            postedText: nil,
            pageCountText: "2 pages",
            tags: []
        )
    }
}
