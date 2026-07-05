import Foundation

/// Parses one image reader page into the image URL and navigation links.
struct EHImagePageParser {
    /// Parses a reader page using the source URL to recover gallery and page identifiers.
    func parse(_ html: String, sourceURL: URL) throws -> EHImagePage {
        guard let identifiers = imagePageIdentifier(from: sourceURL) else {
            throw EHParseError.missingImagePageIdentifier
        }

        guard
            let imageElement = EHHTMLParsing.element(in: html, id: "img"),
            let imageURL = EHHTMLParsing.url(from: EHHTMLParsing.attribute("src", in: imageElement))
        else {
            throw EHParseError.missingImageURL
        }

        return EHImagePage(
            galleryID: identifiers.galleryID,
            pageNumber: identifiers.pageNumber,
            title: title(in: html),
            imageURL: imageURL,
            previousPageURL: linkByID("prev", in: html),
            nextPageURL: linkByID("next", in: html),
            galleryURL: galleryURL(in: html),
            originalImageURL: originalImageURL(in: html)
        )
    }

    /// Extracts gallery id and page number from a reader URL.
    private func imagePageIdentifier(from url: URL) -> (galleryID: Int, pageNumber: Int)? {
        guard
            let match = EHHTMLParsing.firstMatch(in: url.path, pattern: #"^/s/[a-z0-9]+/([0-9]+)-([0-9]+)$"#),
            match.count >= 3,
            let galleryID = Int(match[1]),
            let pageNumber = Int(match[2])
        else {
            return nil
        }
        return (galleryID, pageNumber)
    }

    /// Reads the page title from the top reader block.
    private func title(in html: String) -> String? {
        guard
            let i1 = EHHTMLParsing.element(in: html, id: "i1"),
            let value = EHHTMLParsing.firstMatch(in: i1, pattern: #"<h1[^>]*>(.*?)</h1>"#)?.dropFirst().first
        else {
            return nil
        }
        let text = EHHTMLParsing.textContent(value)
        return text.isEmpty ? nil : text
    }

    /// Reads the first link URL for a duplicated navigation id.
    private func linkByID(_ id: String, in html: String) -> URL? {
        let pattern = #"<a[^>]*id="\#(id)"[^>]*href="([^"]+)""#
        return EHHTMLParsing.url(from: EHHTMLParsing.firstMatch(in: html, pattern: pattern)?.dropFirst().first)
    }

    /// Reads the link back to the gallery detail page.
    private func galleryURL(in html: String) -> URL? {
        guard let i5 = EHHTMLParsing.element(in: html, id: "i5") else { return nil }
        return EHHTMLParsing.url(
            from: EHHTMLParsing.firstMatch(in: i5, pattern: #"href="(https://e-hentai\.org/g/[0-9]+/[a-z0-9]+/)""#)?.dropFirst().first
        )
    }

    /// Reads the original image link when the page exposes it.
    private func originalImageURL(in html: String) -> URL? {
        guard let i6 = EHHTMLParsing.element(in: html, id: "i6") else { return nil }
        return EHHTMLParsing.url(
            from: EHHTMLParsing.firstMatch(in: i6, pattern: #"href="(https://e-hentai\.org/fullimg/[^"]+)""#)?.dropFirst().first
        )
    }
}

