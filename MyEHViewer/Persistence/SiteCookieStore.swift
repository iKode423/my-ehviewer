import Combine
import Foundation
import Security

/// Stores the optional site cookie header used for account-aware browsing.
@MainActor
final class SiteCookieStore: ObservableObject {
    static let shared = SiteCookieStore()

    @Published private(set) var cookieHeader = ""
    @Published private(set) var errorMessage: String?

    private let storage: SiteCookieSecretStorage

    var hasCookieHeader: Bool {
        !cookieHeader.isEmpty
    }

    var cookieHeaderForRequest: String? {
        cookieHeader.isEmpty ? nil : cookieHeader
    }

    /// Creates a store backed by secure local storage.
    init(storage: SiteCookieSecretStorage = KeychainSiteCookieSecretStorage()) {
        self.storage = storage
        do {
            cookieHeader = try storage.readCookieHeader() ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a normalized cookie header for future site requests.
    func saveCookieHeader(_ rawHeader: String) {
        let normalizedHeader = Self.normalizedCookieHeader(rawHeader)
        do {
            if normalizedHeader.isEmpty {
                try storage.deleteCookieHeader()
            } else {
                try storage.saveCookieHeader(normalizedHeader)
            }
            cookieHeader = normalizedHeader
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes the configured cookie header from local storage.
    func clearCookieHeader() {
        do {
            try storage.deleteCookieHeader()
            cookieHeader = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Normalizes pasted cookie text into one HTTP Cookie header value.
    static func normalizedCookieHeader(_ rawHeader: String) -> String {
        rawHeader
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: "\r", with: ";")
            .split(separator: ";")
            .map { part in
                String(part)
                    .replacingOccurrences(of: "Cookie:", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
    }
}

/// Defines the small secure-storage surface used by SiteCookieStore.
protocol SiteCookieSecretStorage {
    /// Reads a cookie header from storage.
    func readCookieHeader() throws -> String?

    /// Saves a cookie header to storage.
    func saveCookieHeader(_ cookieHeader: String) throws

    /// Deletes the cookie header from storage.
    func deleteCookieHeader() throws
}

/// Stores the site cookie header in the user's Keychain.
struct KeychainSiteCookieSecretStorage: SiteCookieSecretStorage {
    private let service = "com.ikode.MyEHViewer.site-cookie"
    private let account = "e-hentai-cookie-header"

    /// Reads the saved cookie header from Keychain.
    func readCookieHeader() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SiteCookieStoreError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw SiteCookieStoreError.invalidStoredValue
        }
        return String(data: data, encoding: .utf8)
    }

    /// Saves a cookie header to Keychain.
    func saveCookieHeader(_ cookieHeader: String) throws {
        guard let data = cookieHeader.data(using: .utf8) else {
            throw SiteCookieStoreError.encodingFailed
        }

        try deleteCookieHeader()

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SiteCookieStoreError.keychainStatus(status)
        }
    }

    /// Deletes the saved cookie header from Keychain.
    func deleteCookieHeader() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SiteCookieStoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Describes local secure-storage failures.
enum SiteCookieStoreError: LocalizedError {
    case encodingFailed
    case invalidStoredValue
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Cookie 无法编码。"
        case .invalidStoredValue:
            "本地 Cookie 数据无效。"
        case .keychainStatus(let status):
            "Keychain 返回状态码 \(status)。"
        }
    }
}
