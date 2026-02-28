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
}
