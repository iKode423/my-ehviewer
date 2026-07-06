import Foundation

/// Provides small HTML extraction helpers for the site's predictable public pages.
struct EHHTMLParsing {
    /// Returns the capture groups from the first regular expression match.
    static func firstMatch(in text: String, pattern: String) -> [String]? {
        matches(in: text, pattern: pattern).first
    }

    /// Returns capture groups from all regular expression matches.
    static func matches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let matchRange = match.range(at: index)
                guard let range = Range(matchRange, in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    /// Returns the first HTML element string with the given id.
    static func element(in html: String, id: String) -> String? {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let pattern = #"<([a-z0-9]+)\b[^>]*id="\#(escapedID)"[^>]*>"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
            let startTagRange = Range(match.range(at: 0), in: html),
            let tagRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        let tag = String(html[tagRange]).lowercased()
        let startTag = String(html[startTagRange])
        if startTag.hasSuffix("/>") || voidTags.contains(tag) {
            return startTag
        }

        return balancedElement(in: html, tag: tag, startTagRange: startTagRange)
    }

    /// Returns the first attribute value from an HTML element string.
    static func attribute(_ name: String, in element: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\#(escapedName)\s*=\s*(['"])(.*?)\1"#
        guard let match = firstMatch(in: element, pattern: pattern), match.count >= 3 else {
            return nil
        }
        return decodeEntities(match[2])
    }

    /// Removes tags and decodes common HTML entities.
    static func textContent(_ html: String) -> String {
        let withoutScripts = html.replacingOccurrences(
            of: #"<script\b[^>]*>.*?</script>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutTags = withoutScripts.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return normalizeWhitespace(decodeEntities(withoutTags))
    }

    /// Decodes the small set of entities commonly found in site titles and tags.
    static func decodeEntities(_ text: String) -> String {
        var decoded = text
        let replacements = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#039;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        for (entity, value) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }

        decoded = decodeNumericEntities(in: decoded, pattern: #"&#(\d+);"#, radix: 10)
        decoded = decodeNumericEntities(in: decoded, pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        return decoded
    }

    /// Collapses repeated whitespace into a single readable separator.
    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts an absolute URL from a captured string.
    static func url(from value: String?) -> URL? {
        guard let value else { return nil }
        let decoded = decodeEntities(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        guard !decoded.hasPrefix("data:") else { return nil }
        return URL(string: decoded)
    }

    /// Decodes decimal or hexadecimal numeric HTML entities.
    private static func decodeNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()

        for match in matches {
            guard
                let fullRange = Range(match.range(at: 0), in: result),
                let valueRange = Range(match.range(at: 1), in: text),
                let scalarValue = UInt32(text[valueRange], radix: radix),
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }

            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return result
    }

    /// Lists tags that do not have closing tags in HTML fragments.
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]

    /// Returns a same-tag balanced element range for nested site containers.
    private static func balancedElement(in html: String, tag: String, startTagRange: Range<String.Index>) -> String? {
        let pattern = #"</?\#(NSRegularExpression.escapedPattern(for: tag))\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        var depth = 1
        var searchStart = startTagRange.upperBound

        while searchStart < html.endIndex {
            let searchRange = NSRange(searchStart..<html.endIndex, in: html)
            guard
                let match = regex.firstMatch(in: html, range: searchRange),
                let tokenRange = Range(match.range(at: 0), in: html)
            else {
                return String(html[startTagRange.lowerBound..<html.endIndex])
            }

            let token = html[tokenRange].lowercased()
            if token.hasPrefix("</") {
                depth -= 1
            } else if !token.hasSuffix("/>") {
                depth += 1
            }

            if depth == 0 {
                return String(html[startTagRange.lowerBound..<tokenRange.upperBound])
            }

            searchStart = tokenRange.upperBound
        }

        return nil
    }
}
