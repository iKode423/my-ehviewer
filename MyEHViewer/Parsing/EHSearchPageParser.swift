import Foundation

/// Parses the site's compact search result table into app models.
struct EHSearchPageParser {
    private let resultsPerPage = 25

    /// Parses a search HTML page and returns result rows with pagination links.
    func parse(_ html: String) -> EHSearchPage {
        let rows = EHHTMLParsing.matches(in: html, pattern: #"<tr\b[^>]*>.*?</tr>"#)
            .compactMap(\.first)
            .filter { $0.contains("/g/") && $0.contains("glname") }
        let totalResultCount = totalResultCount(in: html)

        return EHSearchPage(
            results: rows.compactMap(parseResult),
            nextPageURL: paginationURL(in: html, ids: ["unext", "dnext"]),
            previousPageURL: paginationURL(in: html, ids: ["uprev", "dprev"]),
            totalResultCount: totalResultCount?.count,
            totalPageCount: totalResultCount.map { pageCount(for: $0.count) },
            isTotalResultCountApproximate: totalResultCount?.isApproximate ?? false
        )
    }

    /// Parses one result table row.
    private func parseResult(_ row: String) -> EHSearchResult? {
        guard
            let match = EHHTMLParsing.firstMatch(
                in: row,
                pattern: #"href="(https://e-hentai\.org/g/([0-9]+)/([a-z0-9]+)/?)""#
            ),
            match.count >= 4,
            let pageURL = URL(string: match[1]),
            let gid = Int(match[2])
        else {
            return nil
        }

        let title = firstText(in: row, pattern: #"<div class="glink"[^>]*>(.*?)</div>"#)
        let category = firstText(in: row, pattern: #"<div class="cn [^"]*"[^>]*>(.*?)</div>"#)
        let thumbnailURL = thumbnailURL(in: row)

        return EHSearchResult(
            identifier: EHGalleryIdentifier(gid: gid, token: match[3]),
            title: title,
            category: category,
            pageURL: pageURL,
            thumbnailURL: thumbnailURL,
            uploader: firstText(in: row, pattern: #"<td class="gl4c[^"]*"[^>]*>\s*<div[^>]*>\s*<a[^>]*>(.*?)</a>"#),
            postedText: firstText(in: row, pattern: #"id="posted_[0-9]+"[^>]*>(.*?)</div>"#),
            pageCountText: firstText(in: row, pattern: #">([0-9]+\s+pages)<"#),
            tags: tags(in: row)
        )
    }

    /// Reads the first text capture from a fragment.
    private func firstText(in html: String, pattern: String) -> String {
        guard let value = EHHTMLParsing.firstMatch(in: html, pattern: pattern)?.dropFirst().first else {
            return ""
        }
        return EHHTMLParsing.textContent(value)
    }

    /// Picks the lazy thumbnail URL, normal image source, or CSS background image.
    private func thumbnailURL(in row: String) -> URL? {
        if let image = EHHTMLParsing.firstMatch(in: row, pattern: #"<img\b[^>]*>"#)?.first {
            let lazyURL = EHHTMLParsing.attribute("data-src", in: image)
            let srcURL = EHHTMLParsing.attribute("src", in: image)
            if let url = EHHTMLParsing.url(from: lazyURL) ?? EHHTMLParsing.url(from: srcURL) {
                return url
            }
        }

        let styleURL = EHHTMLParsing.firstMatch(
            in: row,
            pattern: #"url\((?:'|")?([^)'"]+)(?:'|")?\)"#
        )?.dropFirst().first
        return EHHTMLParsing.url(from: styleURL)
    }

    /// Parses compact tag title attributes such as `artist:name`.
    private func tags(in row: String) -> [EHTag] {
        EHHTMLParsing.matches(in: row, pattern: #"class="gt"[^>]*title="([^"]+)""#)
            .compactMap { $0.dropFirst().first }
            .map(EHHTMLParsing.decodeEntities)
            .compactMap(parseTag)
    }

    /// Converts a raw tag string into a namespaced tag model.
    private func parseTag(_ rawValue: String) -> EHTag? {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return EHTag(namespace: parts[0], name: parts[1])
    }

    /// Finds the first available pagination link by id.
    private func paginationURL(in html: String, ids: [String]) -> URL? {
        for id in ids {
            let pattern = #"<a[^>]*id="\#(id)"[^>]*href="([^"]+)""#
            if let value = EHHTMLParsing.firstMatch(in: html, pattern: pattern)?.dropFirst().first {
                return EHHTMLParsing.url(from: value)
            }
        }
        return nil
    }

    /// Reads the aggregate result count shown above E-Hentai search results.
    private func totalResultCount(in html: String) -> (count: Int, isApproximate: Bool)? {
        guard
            let match = EHHTMLParsing.firstMatch(in: html, pattern: #"Found( about)?\s+([0-9,]+)\s+results?"#),
            match.count >= 3
        else {
            return nil
        }
        let rawCount = match[2].replacingOccurrences(of: ",", with: "")
        guard let count = Int(rawCount) else { return nil }
        return (count, match[1].isEmpty == false)
    }

    /// Estimates total search pages using the compact result page size.
    private func pageCount(for totalResultCount: Int) -> Int {
        guard totalResultCount > 0 else { return 0 }
        return Int(ceil(Double(totalResultCount) / Double(resultsPerPage)))
    }
}
