import CryptoKit
import Foundation

private struct HitomiGalleryInfo: Decodable {
    let id: String
    let title: String
    let japaneseTitle: String?
    let type: String?
    let language: String?
    let languageLocalName: String?
    let date: String?
    let galleryURL: String?
    let related: [Int]?
    let files: [HitomiFile]
    let artists: [HitomiNamedItem]?
    let groups: [HitomiNamedItem]?
    let parodys: [HitomiNamedItem]?
    let characters: [HitomiNamedItem]?
    let tags: [HitomiTag]?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case japaneseTitle = "japanese_title"
        case type
        case language
        case languageLocalName = "language_localname"
        case date
        case galleryURL = "galleryurl"
        case related
        case files
        case artists
        case groups
        case parodys
        case characters
        case tags
    }

    /// Decodes older gallery records whose numeric id was not serialized as a string.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        title = try container.decode(String.self, forKey: .title)
        japaneseTitle = try container.decodeIfPresent(String.self, forKey: .japaneseTitle)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        languageLocalName = try container.decodeIfPresent(String.self, forKey: .languageLocalName)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        galleryURL = try container.decodeIfPresent(String.self, forKey: .galleryURL)
        related = try container.decodeIfPresent([Int].self, forKey: .related)
        files = try container.decode([HitomiFile].self, forKey: .files)
        artists = try container.decodeIfPresent([HitomiNamedItem].self, forKey: .artists)
        groups = try container.decodeIfPresent([HitomiNamedItem].self, forKey: .groups)
        parodys = try container.decodeIfPresent([HitomiNamedItem].self, forKey: .parodys)
        characters = try container.decodeIfPresent([HitomiNamedItem].self, forKey: .characters)
        tags = try container.decodeIfPresent([HitomiTag].self, forKey: .tags)
    }
}

private struct HitomiFile: Decodable {
    let name: String
    let width: Int?
    let height: Int?
    let hash: String
    let hasWebP: Int?
    let hasAVIF: Int?

    private enum CodingKeys: String, CodingKey {
        case name
        case width
        case height
        case hash
        case hasWebP = "haswebp"
        case hasAVIF = "hasavif"
    }
}

private struct HitomiNamedItem: Decodable {
    let artist: String?
    let group: String?
    let parody: String?
    let character: String?
}

private struct HitomiTag: Decodable {
    let tag: String
    let male: Bool
    let female: Bool

    private enum CodingKeys: String, CodingKey {
        case tag
        case male
        case female
    }

    /// Decodes gender flags emitted as strings, integers, or booleans.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decode(String.self, forKey: .tag)
        male = Self.decodeFlag(from: container, forKey: .male)
        female = Self.decodeFlag(from: container, forKey: .female)
    }

    /// Converts legacy flag representations into one boolean value.
    private static func decodeFlag(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Bool {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value ?? false
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return (value ?? 0) != 0
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && normalized != "0" && normalized != "false"
        }
        return false
    }
}

private struct HitomiSearchIDPage {
    let ids: [Int]
    let totalCount: Int?
}

@MainActor
final class HitomiDataSource {
    private let client: EHDataHTTPClient
    private let rangeDataLoader: (URL, ClosedRange<UInt64>) async throws -> Data
    private let galleriesPerPage = 25
    private let contentBaseURL = URL(string: "https://ltn.gold-usergeneratedcontent.net/")!
    private let tagIndexBaseURL = URL(string: "https://tagindex.hitomi.la/")!
    private let indexURL = URL(string: "https://ltn.gold-usergeneratedcontent.net/n/index-all.nozomi")!
    private let galleryInfoBaseURL = URL(string: "https://ltn.gold-usergeneratedcontent.net/galleries/")!
    private let siteBaseURL = URL(string: "https://hitomi.la/")!
    private let imageBaseURL = URL(string: "https://a.hitomi.la/")!
    private let imageContentBaseURL = URL(string: "https://a.gold-usergeneratedcontent.net/")!
    private let imageContextURL = URL(string: "https://ltn.gold-usergeneratedcontent.net/gg.js")!
    private let maxSearchNodeSize = 464
    private let resultsPerPage = 25
    private let previewPageBatchSize = 20
    private var galleriesIndexVersion: String?
    private var imageContext: HitomiImageContext?

    /// Creates a Hitomi data source backed by the shared HTTP client.
    init(
        client: EHDataHTTPClient = URLSessionEHHTTPClient(),
        rangeDataLoader: @escaping (URL, ClosedRange<UInt64>) async throws -> Data = HitomiDataSource.defaultRangeData
    ) {
        self.client = client
        self.rangeDataLoader = rangeDataLoader
    }

    /// Loads one browse or search page from Hitomi's static indexes.
    func searchPage(keyword: String, pageNumber: Int) async throws -> EHSearchPage {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePageNumber = max(1, pageNumber)
        let idPage: HitomiSearchIDPage
        if trimmedKeyword.isEmpty {
            idPage = HitomiSearchIDPage(ids: try await loadGalleryIDs(pageNumber: safePageNumber), totalCount: nil)
        } else {
            idPage = try await hitomiSearchGalleryIDs(query: trimmedKeyword, pageNumber: safePageNumber)
        }
        let details = try await loadGalleryInfos(for: idPage.ids)
        var results: [EHSearchResult] = []
        for detail in details {
            results.append(try await searchResult(from: detail))
        }
        let totalPageCount = idPage.totalCount.map { pageCount(for: $0) }
        return EHSearchPage(
            results: results,
            nextPageURL: nextHitomiPageURL(currentPageNumber: safePageNumber, totalPageCount: totalPageCount),
            previousPageURL: safePageNumber > 1 ? hitomiPageURL(pageNumber: safePageNumber - 1) : nil,
            totalResultCount: idPage.totalCount,
            totalPageCount: totalPageCount
        )
    }

    /// Loads gallery metadata from Hitomi's static gallery info script.
    func galleryDetail(from pageURL: URL) async throws -> EHGalleryDetail {
        let info = try await galleryInfo(from: pageURL)
        return try await detail(from: info)
    }

    /// Loads one batch of Hitomi preview page links from gallery metadata.
    func galleryPageLinks(from pageURL: URL, startPage: Int, limit: Int = 20) async throws -> [EHGalleryPageLink] {
        let info = try await galleryInfo(from: pageURL)
        return try await pageLinks(from: info, startIndex: max(0, startPage - 1), limit: limit)
    }

    /// Builds a reader page directly from Hitomi gallery metadata.
    func imagePage(from pageURL: URL) async throws -> EHImagePage {
        guard
            let identifiers = hitomiImagePageIdentifier(from: pageURL),
            identifiers.pageNumber > 0
        else {
            throw EHParseError.missingImagePageIdentifier
        }

        let info = try await galleryInfo(for: identifiers.galleryID)
        let files = info.files
        guard files.indices.contains(identifiers.pageNumber - 1) else {
            throw EHParseError.missingImageURL
        }

        let pageNumber = identifiers.pageNumber
        let file = files[pageNumber - 1]
        let galleryURL = galleryURL(for: identifiers.galleryID, galleryPath: info.galleryURL)
        return EHImagePage(
            galleryID: identifiers.galleryID,
            pageNumber: pageNumber,
            pageURL: hitomiReaderURL(galleryID: identifiers.galleryID, pageNumber: pageNumber),
            title: info.japaneseTitle ?? info.title,
            imageURL: try await imageURL(for: file, variant: file.hasAVIF == 1 ? .avif : .webp),
            previousPageURL: pageNumber > 1 ? hitomiReaderURL(galleryID: identifiers.galleryID, pageNumber: pageNumber - 1) : nil,
            nextPageURL: pageNumber < files.count ? hitomiReaderURL(galleryID: identifiers.galleryID, pageNumber: pageNumber + 1) : nil,
            galleryURL: galleryURL,
            originalImageURL: try await imageURL(for: file, variant: .original)
        )
    }

    /// Returns the image URL used for one Hitomi file preview.
    private func thumbnailURL(for file: HitomiFile) async throws -> URL {
        try await imageURL(for: file, variant: file.hasAVIF == 1 ? .smallAVIFThumbnail : .smallWebPThumbnail)
    }

    /// Loads a range of gallery ids from the big-endian nozomi index.
    private func loadGalleryIDs(pageNumber: Int) async throws -> [Int] {
        let startByte = (pageNumber - 1) * galleriesPerPage * 4
        let endByte = startByte + galleriesPerPage * 4 - 1
        return decodeNozomiIDs(try await data(from: indexURL, range: UInt64(startByte)...UInt64(endByte)))
    }

    /// Decodes the nozomi index format into gallery ids.
    private func decodeNozomiIDs(_ data: Data) -> [Int] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - bytes.count % 4, by: 4).map { offset in
            let value = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
            return Int(value)
        }
    }

    /// Resolves a Hitomi search query using the same positive, negative, and OR term rules as the web page.
    private func hitomiSearchGalleryIDs(query: String, pageNumber: Int) async throws -> HitomiSearchIDPage {
        let plan = HitomiSearchPlan(query: query)
        var positiveTerms = plan.positiveTerms
        var results: [Int]
        if positiveTerms.isEmpty || (!positiveTerms[0].contains(":") && plan.state.orderKey != .added) {
            results = try await galleryIDs(fromNozomiState: plan.state)
        } else {
            let firstTerm = positiveTerms.removeFirst()
            results = try await galleryIDs(forSearchTerm: firstTerm, state: plan.state)
        }

        order(&results, using: plan.state)

        for orGroup in plan.orTerms {
            var union = Set<Int>()
            for term in orGroup {
                let ids = try await galleryIDs(forSearchTerm: term, state: plan.state)
                union.formUnion(ids)
            }
            results = results.filter { union.contains($0) }
        }

        for term in positiveTerms {
            let ids = Set(try await galleryIDs(forSearchTerm: term, state: plan.state))
            results = results.filter { ids.contains($0) }
        }

        for term in plan.negativeTerms {
            let ids = Set(try await galleryIDs(forSearchTerm: term, state: plan.state))
            results = results.filter { !ids.contains($0) }
        }

        let totalCount = results.count
        let startIndex = max(0, (pageNumber - 1) * resultsPerPage)
        guard startIndex < results.count else {
            return HitomiSearchIDPage(ids: [], totalCount: totalCount)
        }
        let endIndex = min(results.count, startIndex + resultsPerPage)
        return HitomiSearchIDPage(ids: Array(results[startIndex..<endIndex]), totalCount: totalCount)
    }

    /// Loads gallery ids for one Hitomi term, routing namespaced terms to nozomi lists.
    private func galleryIDs(forSearchTerm term: String, state: HitomiSearchState) async throws -> [Int] {
        let normalizedTerm = term.replacingOccurrences(of: "_", with: " ")
        if normalizedTerm.contains(":") {
            var termState = state
            let parts = normalizedTerm.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [] }
            switch parts[0] {
            case "female", "male":
                termState.area = "tag"
                termState.tag = normalizedTerm
            case "language":
                termState.language = parts[1]
            default:
                termState.area = parts[0]
                termState.tag = parts[1]
            }
            return try await galleryIDs(fromNozomiState: termState)
        }

        guard let dataRange = try await searchDataRange(for: normalizedTerm) else {
            return []
        }
        return try await galleryIDs(fromDataRange: dataRange)
    }

    /// Looks up one plain keyword in Hitomi's galleries B-tree index.
    private func searchDataRange(for term: String) async throws -> HitomiSearchDataRange? {
        let version = try await galleriesSearchIndexVersion()
        let indexURL = contentBaseURL
            .appending(path: "galleriesindex")
            .appending(path: "galleries.\(version).index")
        let key = Self.searchHash(for: term)
        var address: UInt64 = 0

        while true {
            let nodeData = try await data(from: indexURL, range: address...(address + UInt64(maxSearchNodeSize) - 1))
            guard let node = HitomiSearchIndexNode(data: nodeData) else { return nil }
            guard !node.keys.isEmpty else { return nil }

            let lookup = node.lookup(key: key)
            if lookup.found {
                return node.dataRanges[lookup.index]
            }
            guard !node.isLeaf else { return nil }
            let nextAddress = node.subnodeAddresses[lookup.index]
            guard nextAddress > 0 else { return nil }
            address = nextAddress
        }
    }

    /// Loads gallery ids from the galleries index data file.
    private func galleryIDs(fromDataRange range: HitomiSearchDataRange) async throws -> [Int] {
        let version = try await galleriesSearchIndexVersion()
        let dataURL = contentBaseURL
            .appending(path: "galleriesindex")
            .appending(path: "galleries.\(version).data")
        let startOffset = range.offset + 4
        let endOffset = range.offset + UInt64(range.length) - 1
        guard endOffset >= startOffset else { return [] }
        let data = try await data(from: dataURL, range: startOffset...endOffset)
        return decodeNozomiIDs(data)
    }

    /// Loads a full Hitomi nozomi list for namespaced search terms.
    private func galleryIDs(fromNozomiState state: HitomiSearchState) async throws -> [Int] {
        let url = nozomiURL(for: state)
        let response = try await client.data(url)
        return decodeNozomiIDs(response.data)
    }

    /// Orders IDs according to the web search state.
    private func order(_ ids: inout [Int], using state: HitomiSearchState) {
        switch state.orderDirection {
        case .ascending:
            ids.reverse()
        case .random:
            ids.shuffle()
        case .descending:
            break
        }
    }

    /// Builds a Hitomi nozomi URL for a namespaced or ordered search state.
    private func nozomiURL(for state: HitomiSearchState) -> URL {
        var components = URLComponents(url: contentBaseURL, resolvingAgainstBaseURL: false)!
        let languageTag = "\(state.tag)-\(state.language)"
        let orderKey = state.orderKey ?? (state.orderBy == .popular ? .year : .added)
        if state.orderBy != .date || orderKey == .published {
            if state.area == "all" {
                components.path = "/n/\(state.orderBy.rawValue)/\(orderKey.rawValue)-\(state.language).nozomi"
            } else {
                components.path = "/n/\(state.area)/\(state.orderBy.rawValue)/\(orderKey.rawValue)/\(languageTag).nozomi"
            }
        } else if state.area == "all" {
            components.path = "/n/\(languageTag).nozomi"
        } else {
            components.path = "/n/\(state.area)/\(languageTag).nozomi"
        }
        return components.url ?? indexURL
    }

    /// Reads and caches the galleries index version used in current Hitomi search URLs.
    private func galleriesSearchIndexVersion() async throws -> String {
        if let galleriesIndexVersion {
            return galleriesIndexVersion
        }
        let url = contentBaseURL
            .appending(path: "galleriesindex")
            .appending(path: "version")
        let response = try await client.get(url)
        let version = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        galleriesIndexVersion = version
        return version
    }

    /// Loads one byte range from Hitomi static content.
    private func data(from url: URL, range: ClosedRange<UInt64>) async throws -> Data {
        try await rangeDataLoader(url, range)
    }

    /// Loads one HTTP byte range from Hitomi static content.
    nonisolated private static func defaultRangeData(from url: URL, range: ClosedRange<UInt64>) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let response = try await URLSession.shared.data(for: request)
        guard let httpResponse = response.1 as? HTTPURLResponse, [200, 206].contains(httpResponse.statusCode) else {
            throw EHNetworkError.invalidResponse
        }
        return response.0
    }

    /// Loads gallery info scripts for a page of ids.
    private func loadGalleryInfos(for galleryIDs: [Int]) async throws -> [HitomiGalleryInfo] {
        var details: [HitomiGalleryInfo] = []
        for galleryID in galleryIDs {
            if let info = try? await galleryInfo(for: galleryID) {
                details.append(info)
            }
        }
        return details
    }

    /// Loads and parses one gallery info script by URL.
    private func galleryInfo(from pageURL: URL) async throws -> HitomiGalleryInfo {
        guard let galleryID = hitomiGalleryID(from: pageURL) else {
            throw EHParseError.missingGalleryIdentifier
        }
        return try await galleryInfo(for: galleryID)
    }

    /// Loads and parses one gallery info script by id.
    private func galleryInfo(for galleryID: Int) async throws -> HitomiGalleryInfo {
        let url = galleryInfoBaseURL.appending(path: "\(galleryID).js")
        let response = try await client.get(url)
        let json = response.body
            .replacingOccurrences(of: #"^\s*var\s+galleryinfo\s*=\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #";?\s*$"#, with: "", options: .regularExpression)
        guard let jsonData = json.data(using: .utf8) else {
            throw EHNetworkError.undecodableBody
        }
        return try JSONDecoder().decode(HitomiGalleryInfo.self, from: jsonData)
    }

    /// Converts one Hitomi gallery into a shared detail model.
    private func detail(from info: HitomiGalleryInfo) async throws -> EHGalleryDetail {
        let galleryID = Int(info.id) ?? 0
        let identifier = EHGalleryIdentifier(gid: galleryID, token: "hitomi", site: .hitomi)
        let pageLinks = try await pageLinks(from: info, startIndex: 0, limit: previewPageBatchSize)

        return EHGalleryDetail(
            identifier: identifier,
            title: info.title,
            japaneseTitle: info.japaneseTitle,
            category: info.type ?? "hitomi",
            coverURL: info.files.first == nil ? nil : try await thumbnailURL(for: info.files[0]),
            uploader: firstContributor(from: info),
            metadata: metadata(from: info),
            ratingLabel: nil,
            ratingCount: nil,
            tags: tags(from: info),
            pageLinks: pageLinks,
            thumbnailPageURLs: [],
            pageCount: info.files.count,
            relatedGalleries: try await relatedSearchResults(from: info)
        )
    }

    /// Builds a bounded batch of reader preview links for one Hitomi gallery.
    private func pageLinks(from info: HitomiGalleryInfo, startIndex: Int, limit: Int) async throws -> [EHGalleryPageLink] {
        let galleryID = Int(info.id) ?? 0
        let endIndex = min(info.files.count, startIndex + max(0, limit))
        guard startIndex < endIndex else { return [] }
        var links: [EHGalleryPageLink] = []
        for index in startIndex..<endIndex {
            let file = info.files[index]
            links.append(EHGalleryPageLink(
                pageNumber: index + 1,
                pageURL: hitomiReaderURL(galleryID: galleryID, pageNumber: index + 1),
                thumbnailURL: try await thumbnailURL(for: file),
                thumbnailCrop: nil
            ))
        }
        return links
    }

    /// Converts Hitomi's related gallery ids into regular search result rows.
    private func relatedSearchResults(from info: HitomiGalleryInfo) async throws -> [EHSearchResult] {
        guard let relatedIDs = info.related, !relatedIDs.isEmpty else { return [] }
        let relatedInfos = try await loadGalleryInfos(for: relatedIDs)
        var results: [EHSearchResult] = []
        for relatedInfo in relatedInfos {
            results.append(try await searchResult(from: relatedInfo))
        }
        return results
    }

    /// Converts one Hitomi gallery into a shared search row model.
    private func searchResult(from info: HitomiGalleryInfo) async throws -> EHSearchResult {
        let galleryID = Int(info.id) ?? 0
        let identifier = EHGalleryIdentifier(gid: galleryID, token: "hitomi", site: .hitomi)
        return EHSearchResult(
            identifier: identifier,
            title: info.japaneseTitle ?? info.title,
            category: info.type ?? "hitomi",
            pageURL: galleryURL(for: galleryID, galleryPath: info.galleryURL),
            thumbnailURL: info.files.first == nil ? nil : try await thumbnailURL(for: info.files[0]),
            uploader: firstContributor(from: info),
            postedText: info.date,
            pageCountText: "\(info.files.count) pages",
            tags: searchResultTags(from: info)
        )
    }

    /// Builds metadata rows shown on the gallery page.
    private func metadata(from info: HitomiGalleryInfo) -> [EHMetadataItem] {
        var items: [EHMetadataItem] = []
        let groupTags = info.groups?.compactMap { item -> EHTag? in
            guard let group = item.group, !group.isEmpty else { return nil }
            return EHTag(namespace: "group", name: group)
        } ?? []
        if !groupTags.isEmpty {
            items.append(EHMetadataItem(
                key: "Group",
                value: groupTags.map(\.name).joined(separator: ", "),
                searchTags: groupTags
            ))
        }
        if let type = info.type {
            items.append(EHMetadataItem(key: "类型", value: type))
        }
        if let language = info.languageLocalName ?? info.language {
            items.append(EHMetadataItem(key: "语言", value: language))
        }
        if let date = info.date {
            items.append(EHMetadataItem(key: "日期", value: date))
        }
        items.append(EHMetadataItem(key: "页数", value: "\(info.files.count) pages"))
        return items
    }

    /// Converts Hitomi tags to shared tag models.
    private func tags(from info: HitomiGalleryInfo) -> [EHTag] {
        let baseTags: [EHTag] = info.tags?.map { tag in
            let namespace: String
            if tag.female {
                namespace = "female"
            } else if tag.male {
                namespace = "male"
            } else {
                namespace = "tag"
            }
            return EHTag(namespace: namespace, name: tag.tag)
        } ?? []
        let namedTags = namedTags(from: info.artists, namespace: "artist", value: \.artist) +
            namedTags(from: info.groups, namespace: "group", value: \.group) +
            namedTags(from: info.parodys, namespace: "parody", value: \.parody) +
            namedTags(from: info.characters, namespace: "character", value: \.character)
        return deduplicatedTags(baseTags + namedTags)
    }

    /// Converts Hitomi named metadata into regular searchable tags.
    private func namedTags(
        from items: [HitomiNamedItem]?,
        namespace: String,
        value: KeyPath<HitomiNamedItem, String?>
    ) -> [EHTag] {
        items?.compactMap { item in
            guard let name = item[keyPath: value], !name.isEmpty else { return nil }
            return EHTag(namespace: namespace, name: name)
        } ?? []
    }

    /// Removes duplicate tags while preserving Hitomi's original order.
    private func deduplicatedTags(_ tags: [EHTag]) -> [EHTag] {
        var seenIDs: Set<String> = []
        return tags.filter { tag in
            seenIDs.insert(tag.id.lowercased()).inserted
        }
    }

    /// Builds search row tags with the gallery language first.
    private func searchResultTags(from info: HitomiGalleryInfo) -> [EHTag] {
        var result = tags(from: info)
        if let language = info.language, !language.isEmpty {
            let languageTag = EHTag(namespace: "language", name: language)
            result.removeAll { $0.id == languageTag.id }
            result.insert(languageTag, at: 0)
        }
        return result
    }

    /// Returns a primary artist or group label.
    private func firstContributor(from info: HitomiGalleryInfo) -> String? {
        info.artists?.compactMap(\.artist).first
            ?? info.groups?.compactMap(\.group).first
            ?? info.parodys?.compactMap(\.parody).first
            ?? info.characters?.compactMap(\.character).first
    }

    /// Builds a canonical Hitomi gallery page URL.
    private func galleryURL(for galleryID: Int, galleryPath: String?) -> URL {
        if let galleryPath, let url = URL(string: galleryPath, relativeTo: siteBaseURL)?.absoluteURL {
            return url
        }
        return siteBaseURL.appending(path: "galleries/\(galleryID).html")
    }

    /// Extracts a Hitomi gallery id from gallery or reader URLs.
    private func hitomiGalleryID(from url: URL) -> Int? {
        if let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"/(?:galleries|reader)/([0-9]+)\.html$"#),
           match.count >= 2 {
            return Int(match[1])
        }
        if let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"^/hitomi/s/([0-9]+)-([0-9]+)$"#),
           match.count >= 2 {
            return Int(match[1])
        }
        if url.host?.contains("hitomi.la") == true,
           let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"-([0-9]+)\.html$"#),
           match.count >= 2 {
            return Int(match[1])
        }
        return nil
    }

    /// Extracts Hitomi gallery and page numbers from synthetic reader URLs.
    private func hitomiImagePageIdentifier(from url: URL) -> (galleryID: Int, pageNumber: Int)? {
        if let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"^/hitomi/s/([0-9]+)-([0-9]+)$"#),
           match.count >= 3,
           let galleryID = Int(match[1]),
           let pageNumber = Int(match[2]) {
            return (galleryID, pageNumber)
        }
        if let galleryID = hitomiGalleryID(from: url) {
            return (galleryID, 1)
        }
        return nil
    }

    /// Builds a synthetic reader URL that the app can route without parsing Hitomi HTML.
    private func hitomiReaderURL(galleryID: Int, pageNumber: Int) -> URL {
        siteBaseURL.appending(path: "hitomi/s/\(galleryID)-\(pageNumber)")
    }

    /// Builds a synthetic search page URL for app pagination state.
    private func hitomiPageURL(pageNumber: Int) -> URL {
        var components = URLComponents(url: siteBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "page", value: String(pageNumber))]
        return components.url ?? siteBaseURL
    }

    /// Returns the next page URL only when a known result set has more pages.
    private func nextHitomiPageURL(currentPageNumber: Int, totalPageCount: Int?) -> URL? {
        if let totalPageCount {
            return currentPageNumber < totalPageCount ? hitomiPageURL(pageNumber: currentPageNumber + 1) : nil
        }
        return hitomiPageURL(pageNumber: currentPageNumber + 1)
    }

    /// Calculates Hitomi result pages from the exact matched id count.
    private func pageCount(for totalResultCount: Int) -> Int {
        guard totalResultCount > 0 else { return 0 }
        return Int(ceil(Double(totalResultCount) / Double(resultsPerPage)))
    }

    /// Generates Hitomi image URLs using the public common.js path rules.
    private func imageURL(for file: HitomiFile, variant: HitomiImageVariant) async throws -> URL {
        switch variant {
        case .smallAVIFThumbnail:
            return thumbnailImageURL(for: file, extension: "avif", sizePath: "avifsmalltn")
        case .smallWebPThumbnail:
            return thumbnailImageURL(for: file, extension: "webp", sizePath: "webpsmalltn")
        case .avif:
            return try await fullSizeImageURL(for: file, extension: "avif")
        case .webp:
            return try await fullSizeImageURL(for: file, extension: "webp")
        case .original:
            let hash = file.hash
            let path = realFullPath(from: hash)
            let originalURL = imageBaseURL
                .appending(path: "images")
                .appending(path: path)
                .deletingPathExtension()
                .appendingPathExtension(file.name.split(separator: ".").last.map(String.init) ?? "jpg")
            return shardedImageURL(from: originalURL)
        }
    }


    /// Builds the current Hitomi full-size media URL using the dynamic gg.js context.
    private func fullSizeImageURL(for file: HitomiFile, extension imageExtension: String) async throws -> URL {
        let context = try await loadImageContext()
        let hashCode = Self.hashCode(from: file.hash)
        let subdomain = "\(imageExtension.prefix(1))\(context.usesSecondSubdomain(for: hashCode) ? 2 : 1)"
        var components = URLComponents(url: imageContentBaseURL, resolvingAgainstBaseURL: false)!
        components.host = "\(subdomain).gold-usergeneratedcontent.net"
        components.path = "/\(context.pathPrefix)\(hashCode)/\(file.hash).\(imageExtension)"
        return components.url ?? imageContentBaseURL
    }

    /// Builds one static Hitomi thumbnail URL on the thumbnail host.
    private func thumbnailImageURL(for file: HitomiFile, extension imageExtension: String, sizePath: String) -> URL {
        var components = URLComponents(url: imageContentBaseURL, resolvingAgainstBaseURL: false)!
        components.host = "tn.gold-usergeneratedcontent.net"
        components.path = "/\(sizePath)/\(realFullPath(from: file.hash)).\(imageExtension)"
        return components.url ?? imageContentBaseURL
    }

    /// Loads and caches Hitomi's image-routing context from gg.js.
    private func loadImageContext() async throws -> HitomiImageContext {
        if let imageContext {
            return imageContext
        }
        let response = try await client.get(imageContextURL)
        let context = try HitomiImageContext(script: response.body)
        imageContext = context
        return context
    }

    /// Returns the hash-based storage path used by current Hitomi image hosts.
    private func realFullPath(from hash: String) -> String {
        let suffix = hash.suffix(3)
        guard suffix.count == 3 else { return hash }
        let first = suffix.suffix(1)
        let second = suffix.prefix(2)
        return "\(first)/\(second)/\(hash)"
    }


    /// Returns the numeric hash bucket used by current Hitomi image hosts.
    nonisolated private static func hashCode(from hash: String) -> Int {
        guard hash.count >= 3 else { return 0 }
        let suffix = hash.suffix(3)
        return Int("\(suffix.suffix(1))\(suffix.prefix(2))", radix: 16) ?? 0
    }

    /// Applies Hitomi's current hash-path based image host sharding rule.
    private func shardedImageURL(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = "\(imageSubdomain(for: url))hitomi.la"
        return components.url ?? url
    }

    /// Returns the image subdomain prefix used by the current common.js script.
    private func imageSubdomain(for url: URL) -> String {
        guard
            let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"/[0-9a-f]/([0-9a-f]{2})/"#),
            match.count >= 2,
            var shardValue = Int(match[1], radix: 16)
        else {
            return "a."
        }

        var frontendCount = 3
        if shardValue < 0x80 {
            frontendCount = 2
        }
        if shardValue < 0x59 {
            shardValue = 1
        }
        let firstScalar = UnicodeScalar(97 + shardValue % frontendCount) ?? "a"
        return "\(Character(firstScalar))b."
    }

    /// Creates the four-byte search key used by Hitomi's B-tree index.
    nonisolated private static func searchHash(for term: String) -> Data {
        Data(SHA256.hash(data: Data(term.utf8)).prefix(4))
    }

    /// Reads one big-endian 32-bit integer from binary index data.
    nonisolated private static func int32(_ data: Data, at offset: Int) -> Int32 {
        let bytes = [UInt8](data)
        guard offset + 4 <= bytes.count else { return 0 }
        let value = UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
        return Int32(bitPattern: value)
    }
}

private struct HitomiImageContext {
    let subdomainCodes: Set<Int>
    let isSuffix2: Bool
    let pathPrefix: String

    /// Parses Hitomi's gg.js image routing context.
    init(script: String) throws {
        let caseMatches = EHHTMLParsing.matches(in: script, pattern: #"case\s+([0-9]+):"#)
        let codes = Set(caseMatches.compactMap { match in
            match.count >= 2 ? Int(match[1]) : nil
        })
        guard !codes.isEmpty else {
            throw EHNetworkError.undecodableBody
        }

        guard
            let rawSuffix = EHHTMLParsing.firstMatch(in: script, pattern: #"var\s+o\s*=\s*([0-9]+)\s*;"#),
            rawSuffix.count >= 2,
            let suffixValue = Int(rawSuffix[1])
        else {
            throw EHNetworkError.undecodableBody
        }

        let pathPrefixMatches = EHHTMLParsing.matches(in: script, pattern: #"b:\s*'([^']*)'"#)
        guard
            let pathPrefixMatch = pathPrefixMatches.last,
            pathPrefixMatch.count >= 2,
            !pathPrefixMatch[1].isEmpty
        else {
            throw EHNetworkError.undecodableBody
        }

        subdomainCodes = codes
        isSuffix2 = suffixValue == 0
        pathPrefix = pathPrefixMatch[1]
    }

    /// Mirrors node-hitomi's nxor rule for choosing a1/a2 and w1/w2 hosts.
    func usesSecondSubdomain(for hashCode: Int) -> Bool {
        subdomainCodes.contains(hashCode) == isSuffix2
    }
}

private struct HitomiSearchPlan {
    var state = HitomiSearchState()
    var positiveTerms: [String] = []
    var negativeTerms: [String] = []
    var orTerms: [[String]] = []

    /// Parses the same search operators that Hitomi's result page recognizes.
    init(query: String) {
        let terms = Self.tokenizedTerms(from: query)

        var groupedOrTerms: [[String]] = [[]]
        for (index, rawTerm) in terms.enumerated() {
            var term = rawTerm
            if applySortOperator(term) {
                continue
            }

            if term == "or" { continue }
            let hasPreviousOr = index > 0 && terms[index - 1] == "or"
            let hasNextOr = index + 1 < terms.count && terms[index + 1] == "or"
            if hasPreviousOr || hasNextOr {
                groupedOrTerms[groupedOrTerms.count - 1].append(term)
                if !hasNextOr {
                    groupedOrTerms.append([])
                }
                continue
            }

            if term.hasPrefix("-") {
                term.removeFirst()
                negativeTerms.append(term)
            } else {
                positiveTerms.append(term)
            }
        }

        positiveTerms.sort { lhs, rhs in
            if lhs.contains(":"), !rhs.contains(":") { return true }
            if !lhs.contains(":"), rhs.contains(":") { return false }
            return false
        }
        orTerms = groupedOrTerms.filter { !$0.isEmpty }

        if state.orderKey == nil {
            state.orderKey = state.orderBy == .popular ? .year : .added
        }
    }

    /// Splits a query while preserving whitespace inside quoted tag values.
    private static func tokenizedTerms(from query: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }

            if character.isWhitespace && !isInsideQuotes {
                appendTerm(current, to: &terms)
                current = ""
            } else {
                current.append(character)
            }
        }
        appendTerm(current, to: &terms)
        return terms
    }

    /// Normalizes and appends one parsed query term when it is not empty.
    private static func appendTerm(_ rawTerm: String, to terms: inout [String]) {
        let term = rawTerm
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        terms.append(term)
    }

    /// Applies one Hitomi sort operator when the token is a recognized operator.
    private mutating func applySortOperator(_ term: String) -> Bool {
        guard term.range(of: #"^(?:sort|order)by(?:key|direction)?:"#, options: .regularExpression) != nil else {
            return false
        }

        let parts = term.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return true }
        let left = parts[0]
        let right = parts[1].filter { $0.isLetter || $0.isNumber }

        if left.range(of: #"^(?:sort|order)(?:by)?key$"#, options: .regularExpression) != nil {
            state.orderKey = HitomiSearchOrderKey(rawValue: right) ?? state.orderKey
        } else if right == "popular" || right == "popularity" {
            state.orderBy = .popular
        } else if right == "date" {
            state.orderBy = .date
        } else if right == "datepublished" {
            state.orderBy = .date
            state.orderKey = .published
        } else if left.range(of: #"^(?:sort|order)by$"#, options: .regularExpression) != nil, right == "random" || right == "rand" {
            state.orderDirection = .random
        } else if left == "orderbydirection" || left == "sortbydirection" {
            state.orderDirection = HitomiSearchOrderDirection(rawValue: right) ?? state.orderDirection
        }
        return true
    }
}

private struct HitomiSearchState {
    var area = "all"
    var tag = "index"
    var language = "all"
    var orderBy = HitomiSearchOrderBy.date
    var orderKey: HitomiSearchOrderKey?
    var orderDirection = HitomiSearchOrderDirection.descending
}

private enum HitomiSearchOrderBy: String {
    case date
    case popular
}

private enum HitomiSearchOrderKey: String {
    case added
    case published
    case today
    case week
    case month
    case year
}

private enum HitomiSearchOrderDirection: String {
    case ascending = "asc"
    case descending = "desc"
    case random
}

private struct HitomiSearchDataRange {
    let offset: UInt64
    let length: Int
}

private struct HitomiSearchIndexNode {
    let keys: [Data]
    let dataRanges: [HitomiSearchDataRange]
    let subnodeAddresses: [UInt64]

    var isLeaf: Bool {
        subnodeAddresses.allSatisfy { $0 == 0 }
    }

    /// Decodes one fixed-size Hitomi B-tree node.
    init?(data: Data) {
        var offset = 0
        let keyCount = Int(Self.int32(data, at: &offset))
        guard keyCount >= 0, keyCount <= 32 else { return nil }

        var decodedKeys: [Data] = []
        for _ in 0..<keyCount {
            let keySize = Int(Self.int32(data, at: &offset))
            guard keySize > 0, keySize <= 31, offset + keySize <= data.count else { return nil }
            decodedKeys.append(Data(data[offset..<offset + keySize]))
            offset += keySize
        }

        let dataCount = Int(Self.int32(data, at: &offset))
        guard dataCount == keyCount else { return nil }
        var decodedRanges: [HitomiSearchDataRange] = []
        for _ in 0..<dataCount {
            let rangeOffset = Self.uint64(data, at: &offset)
            let length = Int(Self.int32(data, at: &offset))
            decodedRanges.append(HitomiSearchDataRange(offset: rangeOffset, length: length))
        }

        var decodedAddresses: [UInt64] = []
        for _ in 0..<17 {
            decodedAddresses.append(Self.uint64(data, at: &offset))
        }

        keys = decodedKeys
        dataRanges = decodedRanges
        subnodeAddresses = decodedAddresses
    }

    /// Returns whether a key exists and the child slot to continue searching when it does not.
    func lookup(key: Data) -> (found: Bool, index: Int) {
        var index = 0
        while index < keys.count {
            let comparison = Self.compare(key, keys[index])
            if comparison <= 0 {
                return (comparison == 0, index)
            }
            index += 1
        }
        return (false, index)
    }

    /// Compares binary keys using Hitomi's byte-wise ordering.
    private static func compare(_ lhs: Data, _ rhs: Data) -> Int {
        let lhsBytes = [UInt8](lhs)
        let rhsBytes = [UInt8](rhs)
        let count = min(lhsBytes.count, rhsBytes.count)
        for index in 0..<count {
            if lhsBytes[index] < rhsBytes[index] { return -1 }
            if lhsBytes[index] > rhsBytes[index] { return 1 }
        }
        return 0
    }

    /// Reads and advances one big-endian 32-bit integer.
    private static func int32(_ data: Data, at offset: inout Int) -> Int32 {
        let bytes = [UInt8](data)
        guard offset + 4 <= bytes.count else { return 0 }
        defer { offset += 4 }
        let value = UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
        return Int32(bitPattern: value)
    }

    /// Reads and advances one big-endian 64-bit integer.
    private static func uint64(_ data: Data, at offset: inout Int) -> UInt64 {
        let bytes = [UInt8](data)
        guard offset + 8 <= bytes.count else { return 0 }
        defer { offset += 8 }
        return bytes[offset..<offset + 8].reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
    }
}

private enum HitomiImageVariant {
    case smallAVIFThumbnail
    case smallWebPThumbnail
    case avif
    case webp
    case original
}
