import Foundation

/// Defines the public E-Hentai base URL used by the app.
enum EHConstants {
    static let baseURL = URL(string: "https://e-hentai.org/")!
}

enum ContentSite: String, CaseIterable, Identifiable, Codable, Sendable {
    case eHentai
    case hitomi

    static let storageKey = "ContentSite.current"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eHentai: AppCopy.siteEHentai
        case .hitomi: AppCopy.siteHitomi
        }
    }

    var baseURL: URL {
        switch self {
        case .eHentai: EHConstants.baseURL
        case .hitomi: URL(string: "https://hitomi.la/")!
        }
    }

    var supportsOnlineFavorites: Bool {
        switch self {
        case .eHentai: true
        case .hitomi: false
        }
    }

    var supportedSearchSources: [EHSearchSource] {
        switch self {
        case .eHentai: EHSearchSource.allCases
        case .hitomi: [.frontPage]
        }
    }

    /// Builds the site-specific exact artist query used from gallery details.
    func artistSearchQuery(for artist: String) -> String {
        switch self {
        case .eHentai:
            return "artist:\"\(artist)$\""
        case .hitomi:
            return "artist:\(artist)"
        }
    }

    /// Resolves a persisted raw value while keeping e-hentai as the stable default.
    static func resolved(rawValue: String) -> ContentSite {
        ContentSite(rawValue: rawValue) ?? .eHentai
    }
}

/// Describes the app-wide appearance preference saved on this device.
enum AppThemeMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    static let storageKey = "App.themeMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: AppCopy.settingsThemeSystem
        case .light: AppCopy.settingsThemeLight
        case .dark: AppCopy.settingsThemeDark
        }
    }
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

    /// Maps a site category label into the app's Chinese display label.
    static func displayName(forSiteLabel label: String) -> String {
        switch label.lowercased() {
        case "doujinshi": EHGalleryCategory.doujinshi.displayName
        case "manga": EHGalleryCategory.manga.displayName
        case "artist cg": EHGalleryCategory.artistCG.displayName
        case "game cg": EHGalleryCategory.gameCG.displayName
        case "western": EHGalleryCategory.western.displayName
        case "non-h": EHGalleryCategory.nonH.displayName
        case "image set": EHGalleryCategory.imageSet.displayName
        case "cosplay": EHGalleryCategory.cosplay.displayName
        case "asian porn": EHGalleryCategory.asianPorn.displayName
        case "misc": EHGalleryCategory.misc.displayName
        default: label
        }
    }
}

/// Identifies a gallery by the numeric id and token used by the site URL.
struct EHGalleryIdentifier: Hashable, Codable, Identifiable, Sendable {
    let gid: Int
    let token: String
    var site: ContentSite

    var id: String {
        switch site {
        case .eHentai: "\(gid)-\(token)"
        case .hitomi: "hitomi-\(gid)"
        }
    }

    /// Creates an identifier from the numeric gallery id, token, and owning site.
    init(gid: Int, token: String, site: ContentSite = .eHentai) {
        self.gid = gid
        self.token = token
        self.site = site
    }

    /// Builds the canonical gallery URL for this identifier.
    func url(baseURL: URL? = nil) -> URL {
        switch site {
        case .eHentai:
            return (baseURL ?? EHConstants.baseURL).appending(path: "g/\(gid)/\(token)/")
        case .hitomi:
            return (baseURL ?? site.baseURL).appending(path: "galleries/\(gid).html")
        }
    }

    /// Builds the site popup URL used to add or update online favorites.
    func favoritePopupURL(baseURL: URL = EHConstants.baseURL) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "gallerypopups.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "gid", value: String(gid)),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "act", value: "addfav")
        ]
        return components.url ?? baseURL.appending(path: "gallerypopups.php")
    }

    /// Extracts a gallery identifier from a canonical gallery URL.
    init?(galleryURL: URL) {
        if let match = EHHTMLParsing.firstMatch(in: galleryURL.path, pattern: #"^/g/([0-9]+)/([a-z0-9]+)/?$"#),
           match.count >= 3,
           let gid = Int(match[1]) {
            self.gid = gid
            self.token = match[2]
            self.site = .eHentai
            return
        }

        if let match = EHHTMLParsing.firstMatch(in: galleryURL.path, pattern: #"^/galleries/([0-9]+)\.html$"#),
           match.count >= 2,
           let gid = Int(match[1]) {
            self.gid = gid
            self.token = "hitomi"
            self.site = .hitomi
            return
        }

        if galleryURL.host?.contains("hitomi.la") == true,
           let match = EHHTMLParsing.firstMatch(in: galleryURL.path, pattern: #"-([0-9]+)\.html$"#),
           match.count >= 2,
           let gid = Int(match[1]) {
            self.gid = gid
            self.token = "hitomi"
            self.site = .hitomi
            return
        }

        return nil
    }

    /// Accepts gallery URLs only from the supported e-hentai and Hitomi hosts.
    init?(supportedGalleryURL: URL) {
        guard let host = supportedGalleryURL.host?.lowercased() else { return nil }
        let isEHentaiHost = host == "e-hentai.org" || host.hasSuffix(".e-hentai.org")
        let isHitomiHost = host == "hitomi.la" || host.hasSuffix(".hitomi.la")
        guard isEHentaiHost || isHitomiHost else { return nil }
        self.init(galleryURL: supportedGalleryURL)
    }

    private enum CodingKeys: String, CodingKey {
        case gid
        case token
        case site
    }

    /// Decodes old e-hentai identifiers that predate the site field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gid = try container.decode(Int.self, forKey: .gid)
        token = try container.decode(String.self, forKey: .token)
        site = try container.decodeIfPresent(ContentSite.self, forKey: .site) ?? .eHentai
    }

    /// Encodes the site field so non-e-hentai galleries remain separated.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gid, forKey: .gid)
        try container.encode(token, forKey: .token)
        try container.encode(site, forKey: .site)
    }
}

/// Describes a rectangular crop inside a larger remote image.
struct EHImageCrop: Hashable, Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
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

    /// Builds the query text used when searching for this tag.
    var searchQuery: String {
        let queryName = name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? name : "\"\(name)\""
        return namespace.isEmpty ? queryName : "\(namespace):\(queryName)"
    }
}

/// Stores one metadata row from a gallery detail page.
struct EHMetadataItem: Hashable, Codable, Identifiable {
    let key: String
    let value: String
    let searchTags: [EHTag]

    var id: String { "\(key)=\(value)" }

    /// Creates a metadata row with optional search links for structured values.
    init(key: String, value: String, searchTags: [EHTag] = []) {
        self.key = key
        self.value = value
        self.searchTags = searchTags
    }
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

    /// Returns tags for search rows with language surfaced first when available.
    var searchRowTags: [EHTag] {
        guard let languageTag = tags.first(where: { $0.namespace == "language" }) else {
            return tags
        }
        return [languageTag] + tags.filter { $0.id != languageTag.id }
    }
}

/// Contains one parsed search response and its pagination links.
struct EHSearchPage: Hashable, Codable {
    let results: [EHSearchResult]
    let nextPageURL: URL?
    let previousPageURL: URL?
    let totalResultCount: Int?
    let totalPageCount: Int?
    let isTotalResultCountApproximate: Bool

    /// Creates a search page with optional aggregate result metadata.
    init(
        results: [EHSearchResult],
        nextPageURL: URL?,
        previousPageURL: URL?,
        totalResultCount: Int? = nil,
        totalPageCount: Int? = nil,
        isTotalResultCountApproximate: Bool = false
    ) {
        self.results = results
        self.nextPageURL = nextPageURL
        self.previousPageURL = previousPageURL
        self.totalResultCount = totalResultCount
        self.totalPageCount = totalPageCount
        self.isTotalResultCountApproximate = isTotalResultCountApproximate
    }
}

/// Represents a link to a readable image page in a gallery.
struct EHGalleryPageLink: Hashable, Codable, Identifiable {
    let pageNumber: Int
    let pageURL: URL
    let thumbnailURL: URL?
    let thumbnailCrop: EHImageCrop?

    var id: Int { pageNumber }

    /// Creates a reader page link with an optional thumbnail image.
    init(pageNumber: Int, pageURL: URL, thumbnailURL: URL? = nil, thumbnailCrop: EHImageCrop? = nil) {
        self.pageNumber = pageNumber
        self.pageURL = pageURL
        self.thumbnailURL = thumbnailURL
        self.thumbnailCrop = thumbnailCrop
    }
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
    let pageCount: Int?
    let relatedGalleries: [EHSearchResult]

    var id: String { identifier.id }

    /// Creates a gallery detail with optional related gallery results.
    init(
        identifier: EHGalleryIdentifier,
        title: String,
        japaneseTitle: String?,
        category: String,
        coverURL: URL?,
        uploader: String?,
        metadata: [EHMetadataItem],
        ratingLabel: String?,
        ratingCount: String?,
        tags: [EHTag],
        pageLinks: [EHGalleryPageLink],
        thumbnailPageURLs: [URL],
        pageCount: Int?,
        relatedGalleries: [EHSearchResult] = []
    ) {
        self.identifier = identifier
        self.title = title
        self.japaneseTitle = japaneseTitle
        self.category = category
        self.coverURL = coverURL
        self.uploader = uploader
        self.metadata = metadata
        self.ratingLabel = ratingLabel
        self.ratingCount = ratingCount
        self.tags = tags
        self.pageLinks = pageLinks
        self.thumbnailPageURLs = thumbnailPageURLs
        self.pageCount = pageCount
        self.relatedGalleries = relatedGalleries
    }
}

/// Represents one online favorite category parsed from the site popup.
struct EHFavoriteCategory: Hashable, Codable, Identifiable {
    let value: String
    let title: String
    let isSelected: Bool

    var id: String { value }
}

/// Contains the favorite popup form endpoint and default fields.
struct EHFavoritePopupForm: Hashable {
    let actionURL: URL
    let fields: [String: String]
    let categories: [EHFavoriteCategory]
    let indicatesFavorite: Bool

    /// Returns true when the popup indicates this gallery already belongs to a favorite category.
    var isFavorited: Bool {
        selectedFavoriteCategory != nil && indicatesFavorite
    }

    /// Returns the checked favorite category while ignoring the site's removal category.
    var selectedFavoriteCategory: EHFavoriteCategory? {
        categories.first { $0.isSelected && $0.value != "-1" }
    }

    /// Returns fields prepared with a category and note for submission.
    func submissionFields(categoryValue: String? = nil, note: String = "") -> [String: String] {
        var values = fields
        let fallbackCategory = selectedFavoriteCategory?.value
            ?? categories.first { $0.value != "-1" }?.value
            ?? values["favcat"]
            ?? "0"
        values["favcat"] = categoryValue ?? fallbackCategory
        values["favnote"] = note
        if !values.keys.contains(where: { ["apply", "update"].contains($0.lowercased()) }) {
            values["update"] = "1"
        }
        return values
    }
}

/// Contains the image URL and navigation links for a reader page.
struct EHImagePage: Hashable, Codable, Identifiable {
    let galleryID: Int
    let pageNumber: Int
    let pageURL: URL
    let title: String?
    let imageURL: URL
    let previousPageURL: URL?
    let nextPageURL: URL?
    let galleryURL: URL?
    let originalImageURL: URL?

    var id: String { "\(galleryID)-\(pageNumber)" }
}

/// Describes the browse endpoint used by search results.
enum EHSearchSource: String, CaseIterable, Identifiable, Codable {
    case frontPage
    case popular
    case watched
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontPage: AppCopy.searchSourceFrontPage
        case .popular: AppCopy.searchSourcePopular
        case .watched: AppCopy.searchSourceWatched
        case .favorites: AppCopy.searchSourceFavorites
        }
    }

    /// Returns the path used by the site's browse endpoint.
    var path: String {
        switch self {
        case .frontPage: "/"
        case .popular: "/popular"
        case .watched: "/watched"
        case .favorites: "/favorites.php"
        }
    }
}

/// Describes search options that map directly to the site's query parameters.
struct EHSearchRequest: Hashable, Codable {
    var source = EHSearchSource.frontPage
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
    var pageIndex: Int?
    var cursor: EHSearchCursor?

    /// Builds a site URL using the currently documented public search parameters.
    func url(baseURL: URL = EHConstants.baseURL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = source.path
        var items: [URLQueryItem] = []

        if source == .favorites {
            items.append(URLQueryItem(name: "favcat", value: "all"))
        }

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

        if let pageIndex {
            items.append(URLQueryItem(name: "range", value: String(max(0, pageIndex))))
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

/// Describes the reader image layout preference saved on this device.
enum ReaderFitMode: String, CaseIterable, Identifiable, Codable {
    case fitPage
    case fitWidth

    static let storageKey = "Reader.fitMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitPage: AppCopy.readerFitPage
        case .fitWidth: AppCopy.readerFitWidth
        }
    }
}

/// Describes the reader zoom preference saved on this device.
enum ReaderZoomLevel: Double, CaseIterable, Identifiable, Codable {
    case x1 = 1.0
    case x125 = 1.25
    case x15 = 1.5
    case x2 = 2.0
    case x3 = 3.0

    static let storageKey = "Reader.zoomLevel"

    var id: Double { rawValue }

    var title: String {
        "\(Int(rawValue * 100))%"
    }

    /// Returns the zoom level used after a double tap.
    var doubleTapTarget: ReaderZoomLevel {
        self == .x1 ? .x2 : .x1
    }

    /// Resolves a persisted value into a known zoom level.
    static func resolved(rawValue: Double) -> ReaderZoomLevel {
        ReaderZoomLevel(rawValue: rawValue) ?? .x1
    }
}

/// Describes the reader background preference saved on this device.
enum ReaderBackgroundMode: String, CaseIterable, Identifiable, Codable {
    case system
    case dark
    case paper

    static let storageKey = "Reader.backgroundMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: AppCopy.readerBackgroundSystem
        case .dark: AppCopy.readerBackgroundDark
        case .paper: AppCopy.readerBackgroundPaper
        }
    }
}
