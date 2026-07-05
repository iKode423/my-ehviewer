import XCTest
@testable import MyEHViewer

/// Verifies local site cookie storage without using the real Keychain.
@MainActor
final class SiteCookieStoreTests: XCTestCase {
    /// Confirms pasted cookie text is normalized into one header line.
    func testNormalizeCookieHeader() {
        let header = SiteCookieStore.normalizedCookieHeader("Cookie: alpha=1;\n beta=2 ; ; gamma=3")

        XCTAssertEqual(header, "alpha=1; beta=2; gamma=3")
    }

    /// Confirms the store can save and clear cookie state.
    func testSaveAndClearCookieHeader() {
        let storage = MemorySiteCookieSecretStorage()
        let store = SiteCookieStore(storage: storage)

        store.saveCookieHeader("alpha=1; beta=2")
        XCTAssertEqual(store.cookieHeaderForRequest, "alpha=1; beta=2")
        XCTAssertEqual(storage.cookieHeader, "alpha=1; beta=2")

        store.clearCookieHeader()
        XCTAssertNil(store.cookieHeaderForRequest)
        XCTAssertNil(storage.cookieHeader)
    }
}

/// Provides in-memory cookie storage for tests.
private final class MemorySiteCookieSecretStorage: SiteCookieSecretStorage {
    var cookieHeader: String?

    /// Reads the in-memory cookie header.
    func readCookieHeader() throws -> String? {
        cookieHeader
    }

    /// Saves the in-memory cookie header.
    func saveCookieHeader(_ cookieHeader: String) throws {
        self.cookieHeader = cookieHeader
    }

    /// Clears the in-memory cookie header.
    func deleteCookieHeader() throws {
        cookieHeader = nil
    }
}
