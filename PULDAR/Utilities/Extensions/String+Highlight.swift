import SwiftUI

extension String {
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
        let collapsed = self
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !collapsed.isEmpty else { return collapsed }

        return collapsed
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
}
