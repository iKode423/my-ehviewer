import Foundation

/// Defines the public E-Hentai base URL used by the app.
enum EHConstants {
    static let baseURL = URL(string: "https://e-hentai.org/")!
}

/// Represents a gallery category supported by the search page.
enum EHGalleryCategory: Int, CaseIterable, Identifiable, Codable {
    case misc = 1
    case doujinshi = 2
    case manga = 4
    case artistCG = 8
    case gameCG = 16
    case imageSet = 32
    case cosplay = 64
    case asianPorn = 128
    case nonH = 256
    case western = 512

    var id: Int { rawValue }

    /// Returns the Chinese display name shown in filters and gallery rows.
    var displayName: String {
        switch self {
        case .doujinshi: "同人志"
        case .manga: "漫画"
        case .artistCG: "画师 CG"
        case .gameCG: "游戏 CG"
        case .western: "欧美"
        case .nonH: "非成人"
        case .imageSet: "图集"
        case .cosplay: "Cosplay"
        case .asianPorn: "亚洲成人"
        case .misc: "其他"
        }
    }
}

/// Identifies a gallery by the numeric id and token used by the site URL.
struct EHGalleryIdentifier: Hashable, Codable, Identifiable {
    let gid: Int
    let token: String

    var id: String { "\(gid)-\(token)" }

    /// Builds the canonical gallery URL for this identifier.
    func url(baseURL: URL = EHConstants.baseURL) -> URL {
        baseURL.appending(path: "g/\(gid)/\(token)/")
    }
}

/// Describes a namespace tag such as `artist:name` or `language:english`.
struct EHTag: Hashable, Codable, Identifiable {
    let namespace: String
    let name: String

    var id: String { "\(namespace):\(name)" }

    /// Returns the compact label used in lists.
    var displayName: String {
        namespace.isEmpty ? name : "\(namespace):\(name)"
    }
}

/// Stores one metadata row from a gallery detail page.
struct EHMetadataItem: Hashable, Codable, Identifiable {
    let key: String
    let value: String

    var id: String { "\(key)=\(value)" }
}

/// Represents one gallery result on the search page.
struct EHSearchResult: Hashable, Codable, Identifiable {
    let identifier: EHGalleryIdentifier
    let title: String
    let category: String
    let pageURL: URL
    let thumbnailURL: URL?
    let uploader: String?
    let postedText: String?
    let pageCountText: String?
    let tags: [EHTag]

    var id: String { identifier.id }
}

/// Contains one parsed search response and its pagination links.
struct EHSearchPage: Hashable, Codable {
    let results: [EHSearchResult]
    let nextPageURL: URL?
    let previousPageURL: URL?
}

/// Represents a link to a readable image page in a gallery.
struct EHGalleryPageLink: Hashable, Codable, Identifiable {
    let pageNumber: Int
    let pageURL: URL

    var id: Int { pageNumber }
}

/// Contains parsed gallery detail metadata and thumbnail page links.
struct EHGalleryDetail: Hashable, Codable, Identifiable {
    let identifier: EHGalleryIdentifier
    let title: String
    let japaneseTitle: String?
    let category: String
    let coverURL: URL?
    let uploader: String?
    let metadata: [EHMetadataItem]
    let ratingLabel: String?
    let ratingCount: String?
    let tags: [EHTag]
    let pageLinks: [EHGalleryPageLink]
    let thumbnailPageURLs: [URL]

    var id: String { identifier.id }
}

/// Contains the image URL and navigation links for a reader page.
struct EHImagePage: Hashable, Codable, Identifiable {
    let galleryID: Int
    let pageNumber: Int
    let title: String?
    let imageURL: URL
    let previousPageURL: URL?
    let nextPageURL: URL?
    let galleryURL: URL?
    let originalImageURL: URL?

    var id: String { "\(galleryID)-\(pageNumber)" }
}

/// Describes search options that map directly to the site's query parameters.
struct EHSearchRequest: Hashable, Codable {
    var keyword = ""
    var excludedCategories: Set<EHGalleryCategory> = []
    var browseExpunged = false
    var requireTorrent = false
    var minimumPages: Int?
    var maximumPages: Int?
    var minimumRating: Int?
    var disableLanguageFilter = false
    var disableUploaderFilter = false
    var disableTagFilter = false
    var cursor: EHSearchCursor?

    /// Builds a site URL using the currently documented public search parameters.
    func url(baseURL: URL = EHConstants.baseURL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            items.append(URLQueryItem(name: "f_search", value: trimmedKeyword))
        }

        let categoryMask = excludedCategories.reduce(0) { $0 | $1.rawValue }
        if categoryMask > 0 {
            items.append(URLQueryItem(name: "f_cats", value: String(categoryMask)))
        }

        if usesAdvancedOptions {
            items.append(URLQueryItem(name: "advsearch", value: "1"))
            appendFlag("f_sh", enabled: browseExpunged, to: &items)
            appendFlag("f_sto", enabled: requireTorrent, to: &items)
            appendNumber("f_spf", value: minimumPages, to: &items)
            appendNumber("f_spt", value: maximumPages, to: &items)
            appendNumber("f_srdd", value: minimumRating, to: &items)
            appendFlag("f_sfl", enabled: disableLanguageFilter, to: &items)
            appendFlag("f_sfu", enabled: disableUploaderFilter, to: &items)
            appendFlag("f_sft", enabled: disableTagFilter, to: &items)
        }

        if let cursor {
            switch cursor {
            case .next(let gid):
                items.append(URLQueryItem(name: "next", value: String(gid)))
            case .previous(let gid):
                items.append(URLQueryItem(name: "prev", value: String(gid)))
            }
        }

        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? baseURL
    }

    /// Returns true when advanced search parameters must be included.
    private var usesAdvancedOptions: Bool {
        browseExpunged || requireTorrent || minimumPages != nil || maximumPages != nil || minimumRating != nil || disableLanguageFilter || disableUploaderFilter || disableTagFilter
    }

    /// Adds a checked checkbox-style query item when enabled.
    private func appendFlag(_ name: String, enabled: Bool, to items: inout [URLQueryItem]) {
        if enabled {
            items.append(URLQueryItem(name: name, value: "on"))
        }
    }

    /// Adds a positive numeric query item when a value is present.
    private func appendNumber(_ name: String, value: Int?, to items: inout [URLQueryItem]) {
        guard let value, value > 0 else { return }
        items.append(URLQueryItem(name: name, value: String(value)))
    }
}

/// Describes cursor-based search pagination.
enum EHSearchCursor: Hashable, Codable {
    case next(Int)
    case previous(Int)
}

