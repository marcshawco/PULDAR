import SwiftUI

extension String {
    nonisolated private static let merchantAliases: [(contains: [String], replacement: String)] = [
        (["wholefoodsmarket", "wholefoods", "wholefds"], "Whole Foods"),
        (["walmartsupercenter", "walmart", "wmt"], "Walmart"),
        (["target"], "Target"),
        (["starbuckscoffee", "starbucks"], "Starbucks"),
        (["traderjoes", "traderjoe"], "Trader Joe's"),
        (["costcowholesale", "costco"], "Costco"),
        (["safeway"], "Safeway"),
        (["walgreens"], "Walgreens"),
        (["cvspharmacy", "cvs"], "CVS"),
        (["homedepot"], "Home Depot"),
        (["lowesfoods", "lowes"], "Lowe's"),
        (["amazon"], "Amazon"),
        (["chipotlemexicangrill", "chipotlefeedback", "chipotle"], "Chipotle"),
        (["mcdonalds", "mcd"], "McDonald's"),
        (["tacobell"], "Taco Bell"),
        (["subway"], "Subway"),
        (["panerabread", "panera"], "Panera"),
        (["cava"], "CAVA"),
        (["sweetgreen"], "Sweetgreen")
    ]

    /// Return an `AttributedString` with every occurrence of `query`
    /// highlighted in yellow (case-insensitive).
    func highlighted(matching query: String) -> AttributedString {
        var attributed = AttributedString(self)
        guard !query.isEmpty else { return attributed }

        let lowSelf  = self.lowercased()
        let lowQuery = query.lowercased()

        var searchStart = lowSelf.startIndex
        while let range = lowSelf.range(of: lowQuery, range: searchStart..<lowSelf.endIndex) {
            // Map String.Index → AttributedString.Index
            let offset = lowSelf.distance(from: lowSelf.startIndex, to: range.lowerBound)
            let length = lowSelf.distance(from: range.lowerBound, to: range.upperBound)

            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: offset)
            let attrEnd   = attributed.index(attrStart, offsetByCharacters: length)

            attributed[attrStart..<attrEnd].backgroundColor = AppColors.searchHighlight
            searchStart = range.upperBound
        }

        return attributed
    }

    /// Normalize merchant casing for consistent transaction display.
    ///
    /// - Keeps mixed-case brand names as-is.
    /// - Uppercases ticker/symbol style tokens (e.g. `s&p500` -> `S&P500`).
    /// - Title-cases plain lowercase/uppercase words.
    func normalizedMerchantName() -> String {
        let cleaned = self
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)\b(store|st|unit|terminal|lane|register|reg|loc|location|#)\s*[0-9][0-9A-Z-]*\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:www\.)?[a-z0-9.-]+\.(com|net|org)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:tel|phone|ph)\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:customer copy|merchant copy|approved|declined|transaction|receipt)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return cleaned }

        let canonical = Self.canonicalMerchantName(from: cleaned)
        guard canonical == nil else { return canonical! }

        return cleaned
            .split(separator: " ")
            .map { token in
                let raw = String(token)
                if raw.rangeOfCharacter(from: .decimalDigits) != nil || raw.contains("&") {
                    return raw.uppercased()
                }

                if raw != raw.lowercased(), raw != raw.uppercased() {
                    return raw
                }

                guard let first = raw.first else { return raw }
                let head = String(first).uppercased()
                let tail = String(raw.dropFirst()).lowercased()
                return head + tail
            }
            .joined(separator: " ")
    }

    nonisolated static func canonicalMerchantName(from value: String) -> String? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)

        for alias in merchantAliases where alias.contains.contains(where: normalized.contains) {
            return alias.replacement
        }

        return nil
    }
}
