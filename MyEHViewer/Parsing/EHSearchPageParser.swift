import Foundation

/// Parses the site's compact search result table into app models.
struct EHSearchPageParser {
    /// Parses a search HTML page and returns result rows with pagination links.
    func parse(_ html: String) -> EHSearchPage {
        let rows = EHHTMLParsing.matches(in: html, pattern: #"<tr\b[^>]*>.*?</tr>"#)
            .compactMap(\.first)
            .filter { $0.contains("/g/") && $0.contains("glname") }

        return EHSearchPage(
            results: rows.compactMap(parseResult),
            nextPageURL: paginationURL(in: html, ids: ["unext", "dnext"]),
            previousPageURL: paginationURL(in: html, ids: ["uprev", "dprev"])
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

    /// Picks the lazy thumbnail URL when present, otherwise the normal image source.
    private func thumbnailURL(in row: String) -> URL? {
        guard let image = EHHTMLParsing.firstMatch(in: row, pattern: #"<img\b[^>]*>"#)?.first else {
            return nil
        }

        let lazyURL = EHHTMLParsing.attribute("data-src", in: image)
        let srcURL = EHHTMLParsing.attribute("src", in: image)
        return EHHTMLParsing.url(from: lazyURL) ?? EHHTMLParsing.url(from: srcURL)
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
}

