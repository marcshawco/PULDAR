import Foundation

/// The operation the user wants to perform on a Folio item.
enum FolioOperation: String, Codable {
    case add            // "added 250 to savings"
    case subtract       // "paid 580 toward my medical loan"
    case set            // "set my car to 12000"
    case percentChange  // "stocks went up 14%"
}

/// The strict JSON contract between the local LLM and the Folio pipeline.
///
/// The model is prompted to return exactly:
/// ```json
/// {"itemName":"savings","category":"savings","kind":"fund","operation":"add","amount":250,"percent":null}
/// ```
/// All arithmetic is performed in Swift (`FolioEngine`) — the model only
/// identifies the item, the operation, and the number.
struct FolioCommandResult: Codable {
    let itemName: String
    let category: String
    let kind: String
    let operation: String
    let amount: Double?
    let percent: Double?

    /// Canonical category. Swift owns the mapping — falls back to the item
    /// name if the model's category is unusable.
    var folioCategory: FolioCategory {
        let fromCategory = FolioCategory.resolve(category)
        if fromCategory != .other { return fromCategory }
        return FolioCategory.resolve(itemName)
    }

    /// Group for this command. Falls back to the category's kind when the
    /// model omits or mis-states the kind.
    var folioKind: FolioKind {
        let raw = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return FolioKind(rawValue: raw) ?? folioCategory.kind
    }

    var folioOperation: FolioOperation {
        let raw = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let op = FolioOperation(rawValue: raw) {
            return op
        }
        // Infer from the presence of a percentage when the model omits it.
        return resolvedPercent != nil ? .percentChange : .set
    }

    /// Cleaned, non-negative numeric amount, if any.
    var resolvedAmount: Double? {
        guard let amount, amount.isFinite else { return nil }
        return abs(amount)
    }

    /// Signed percentage for `percentChange` (e.g. 14 or -8).
    var resolvedPercent: Double? {
        guard let percent, percent.isFinite else { return nil }
        return percent
    }

    /// A clean display name for a newly created item.
    var resolvedItemName: String {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed.capitalized }
        return folioCategory.displayName
    }
}
