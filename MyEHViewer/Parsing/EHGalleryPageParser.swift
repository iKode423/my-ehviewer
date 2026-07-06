import Foundation

/// Parses a gallery detail page into metadata and reader entry links.
struct EHGalleryPageParser {
    /// Parses detail HTML using the source URL to recover the gallery identifier.
    func parse(_ html: String, sourceURL: URL) throws -> EHGalleryDetail {
        guard let identifier = galleryIdentifier(from: sourceURL) else {
            throw EHParseError.missingGalleryIdentifier
        }

        let title = textByID("gn", in: html)
        guard !title.isEmpty else {
            throw EHParseError.missingGalleryTitle
        }

        return EHGalleryDetail(
            identifier: identifier,
            title: title,
            japaneseTitle: optionalTextByID("gj", in: html),
            category: category(in: html),
            coverURL: coverURL(in: html),
            uploader: uploader(in: html),
            metadata: metadata(in: html),
            ratingLabel: optionalTextByID("rating_label", in: html),
            ratingCount: optionalTextByID("rating_count", in: html),
            tags: tags(in: html),
            pageLinks: pageLinks(in: html),
            thumbnailPageURLs: thumbnailPageURLs(in: html)
        )
    }

    /// Extracts the gallery id and token from a canonical gallery URL.
    private func galleryIdentifier(from url: URL) -> EHGalleryIdentifier? {
        let path = url.path
        guard
            let match = EHHTMLParsing.firstMatch(in: path, pattern: #"^/g/([0-9]+)/([a-z0-9]+)/?$"#),
            match.count >= 3,
            let gid = Int(match[1])
        else {
            return nil
        }
        return EHGalleryIdentifier(gid: gid, token: match[2])
    }

    /// Reads normalized text from an element id.
    private func textByID(_ id: String, in html: String) -> String {
        guard let element = EHHTMLParsing.element(in: html, id: id) else { return "" }
        return EHHTMLParsing.textContent(element)
    }

    /// Reads normalized text from an element id and treats empty strings as missing.
    private func optionalTextByID(_ id: String, in html: String) -> String? {
        let value = textByID(id, in: html)
        return value.isEmpty ? nil : value
    }

    /// Reads the category label from the detail header.
    private func category(in html: String) -> String {
        guard let gdc = EHHTMLParsing.element(in: html, id: "gdc") else { return "" }
        return EHHTMLParsing.textContent(gdc)
    }

    /// Extracts the cover URL from the background style used by the site.
    private func coverURL(in html: String) -> URL? {
        guard
            let gd1 = EHHTMLParsing.element(in: html, id: "gd1"),
            let value = EHHTMLParsing.firstMatch(in: gd1, pattern: #"url\((?:'|")?([^)'"]+)(?:'|")?\)"#)?.dropFirst().first
        else {
            return nil
        }
        return EHHTMLParsing.url(from: value)
    }

    /// Reads the uploader name from the detail header.
    private func uploader(in html: String) -> String? {
        guard
            let gdn = EHHTMLParsing.element(in: html, id: "gdn"),
            let value = EHHTMLParsing.firstMatch(in: gdn, pattern: #"<a[^>]*>(.*?)</a>"#)?.dropFirst().first
        else {
            return nil
        }
        let text = EHHTMLParsing.textContent(value)
        return text.isEmpty ? nil : text
    }

    /// Parses metadata table rows from `#gdd`.
    private func metadata(in html: String) -> [EHMetadataItem] {
        guard let gdd = EHHTMLParsing.element(in: html, id: "gdd") else { return [] }
        return EHHTMLParsing.matches(
            in: gdd,
            pattern: #"<tr>\s*<td class="gdt1"[^>]*>(.*?)</td>\s*<td class="gdt2"[^>]*>(.*?)</td>\s*</tr>"#
        )
        .compactMap { match in
            guard match.count >= 3 else { return nil }
            return EHMetadataItem(
                key: EHHTMLParsing.textContent(match[1]),
                value: EHHTMLParsing.textContent(match[2])
            )
        }
    }

    /// Parses all namespaced tags from `#taglist`.
    private func tags(in html: String) -> [EHTag] {
        guard let taglist = EHHTMLParsing.element(in: html, id: "taglist") else { return [] }
        return EHHTMLParsing.matches(
            in: taglist,
            pattern: #"<a[^>]*id="ta_([^"]+)"[^>]*>(.*?)</a>"#
        )
        .compactMap { match in
            guard match.count >= 3 else { return nil }
            let rawID = match[1].replacingOccurrences(of: "_", with: " ")
            let parts = rawID.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let text = EHHTMLParsing.textContent(match[2])
            return EHTag(namespace: parts[0], name: text.isEmpty ? parts[1] : text)
        }
    }

    /// Parses reader page links from the thumbnail grid.
    private func pageLinks(in html: String) -> [EHGalleryPageLink] {
        guard let gdt = EHHTMLParsing.element(in: html, id: "gdt") else { return [] }
        return EHHTMLParsing.matches(
            in: gdt,
            pattern: #"<a\b[^>]*href="(https://e-hentai\.org/s/[a-z0-9]+/[0-9]+-([0-9]+))"[^>]*>(.*?)</a>"#
        )
        .compactMap { match in
            guard match.count >= 4, let url = URL(string: match[1]), let pageNumber = Int(match[2]) else {
                return nil
            }
            return EHGalleryPageLink(pageNumber: pageNumber, pageURL: url, thumbnailURL: thumbnailURL(in: match[3]))
        }
    }

    /// Picks the thumbnail URL from one gallery page link.
    private func thumbnailURL(in html: String) -> URL? {
        if let image = EHHTMLParsing.firstMatch(in: html, pattern: #"<img\b[^>]*>"#)?.first {
            let lazyURL = EHHTMLParsing.attribute("data-src", in: image)
            let srcURL = EHHTMLParsing.attribute("src", in: image)
            if let url = EHHTMLParsing.url(from: lazyURL) ?? EHHTMLParsing.url(from: srcURL) {
                return url
            }
        }

        let styleURL = EHHTMLParsing.firstMatch(
            in: html,
            pattern: #"url\((?:'|")?([^)'"]+)(?:'|")?\)"#
        )?.dropFirst().first
        return EHHTMLParsing.url(from: styleURL)
    }

    /// Parses thumbnail pagination URLs from the top and bottom pagination bars.
    private func thumbnailPageURLs(in html: String) -> [URL] {
        let urls = EHHTMLParsing.matches(
            in: html,
            pattern: #"href="(https://e-hentai\.org/g/[0-9]+/[a-z0-9]+/\?p=[0-9]+)""#
        )
        .compactMap { $0.dropFirst().first }
        .compactMap(URL.init(string:))

        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }
}

/// Parses the online favorite popup form.
struct EHFavoritePopupParser {
    /// Parses a popup response into a submittable form.
    func parse(_ html: String, sourceURL: URL) -> EHFavoritePopupForm {
        let form = favoriteForm(in: html)
        let resolvedActionURL = form.flatMap { actionURL(in: $0, sourceURL: sourceURL) } ?? sourceURL
        let fields = form.map(inputFields(in:)) ?? fallbackFields()
        let categories = form.map(categories(in:)) ?? []
        return EHFavoritePopupForm(actionURL: resolvedActionURL, fields: fields, categories: categories)
    }

    /// Finds the form that owns favorite category controls.
    private func favoriteForm(in html: String) -> String? {
        EHHTMLParsing.matches(in: html, pattern: #"<form\b[^>]*>.*?</form>"#)
            .compactMap(\.first)
            .first { $0.localizedCaseInsensitiveContains("favcat") || $0.localizedCaseInsensitiveContains("favnote") }
    }

    /// Resolves a form action against the popup response URL.
    private func actionURL(in form: String, sourceURL: URL) -> URL {
        guard
            let startTag = EHHTMLParsing.firstMatch(in: form, pattern: #"<form\b[^>]*>"#)?.first,
            let value = EHHTMLParsing.attribute("action", in: startTag),
            let url = URL(string: value, relativeTo: sourceURL)
        else {
            return sourceURL
        }
        return url.absoluteURL
    }

    /// Parses input and textarea fields while preserving hidden site fields.
    private func inputFields(in form: String) -> [String: String] {
        var fields: [String: String] = [:]
        for input in EHHTMLParsing.matches(in: form, pattern: #"<input\b[^>]*>"#).compactMap(\.first) {
            guard let name = EHHTMLParsing.attribute("name", in: input) else { continue }
            let type = EHHTMLParsing.attribute("type", in: input)?.lowercased() ?? ""
            if type == "radio", name == "favcat", !input.localizedCaseInsensitiveContains("checked") {
                continue
            }
            fields[name] = EHHTMLParsing.attribute("value", in: input) ?? ""
        }

        for match in EHHTMLParsing.matches(in: form, pattern: #"<textarea\b[^>]*name=(['"])(.*?)\1[^>]*>(.*?)</textarea>"#) {
            guard match.count >= 4 else { continue }
            fields[EHHTMLParsing.decodeEntities(match[2])] = EHHTMLParsing.textContent(match[3])
        }

        return fields.merging(fallbackFields()) { current, _ in current }
    }

    /// Parses visible favorite categories from radio controls.
    private func categories(in form: String) -> [EHFavoriteCategory] {
        EHHTMLParsing.matches(
            in: form,
            pattern: #"(<input\b[^>]*name=(['"])favcat\2[^>]*>)(.*?)(?=<input\b[^>]*name=(['"])favcat\4|</form>|<br\s*/?>)"#
        )
        .compactMap { match in
            guard match.count >= 4, let value = EHHTMLParsing.attribute("value", in: match[1]) else { return nil }
            let title = EHHTMLParsing.textContent(match[3])
            return EHFavoriteCategory(
                value: value,
                title: title.isEmpty ? value : title,
                isSelected: match[1].localizedCaseInsensitiveContains("checked")
            )
        }
    }

    /// Provides a minimal favorite form for popup layouts without a form tag.
    private func fallbackFields() -> [String: String] {
        ["favcat": "0", "favnote": "", "update": "1"]
    }
}
