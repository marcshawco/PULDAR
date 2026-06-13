import Foundation
import SwiftData

/// One dated change to a `FolioItem`'s value — the full ledger.
///
/// Every mutation (manual edit or AI command) appends an entry so net worth
/// can be charted over time, browsed in history, and exported.  Entries
/// reference their item by a stored `itemID` rather than a SwiftData
/// relationship, to stay CloudKit-safe and match the existing
/// relationship-free models (`Expense`, `RecurringExpense`).
@Model
final class FolioEntry {
    enum Operation: String, Codable, CaseIterable {
        case add            // money added / balance up
        case subtract       // payment / withdrawal / balance down
        case set            // absolute value assignment
        case percentChange  // relative move (e.g. +14%)
        case create         // item's opening value

        var displayName: String {
            switch self {
            case .add:           return "Added"
            case .subtract:      return "Reduced"
            case .set:           return "Set"
            case .percentChange: return "Changed"
            case .create:        return "Created"
            }
        }
    }

    var id: UUID = UUID()
    var itemID: UUID = UUID()        // FolioItem.id (no SwiftData relationship)
    var itemName: String = ""        // Denormalised snapshot for history/export
    var kind: String = FolioKind.asset.rawValue
    var operation: String = FolioEntry.Operation.set.rawValue
    var delta: Double = 0            // Signed change to currentValue (new − old)
    var resultingValue: Double = 0   // currentValue AFTER this entry
    var percent: Double?             // Populated for percentChange (14 = +14%)
    var date: Date = Date()
    var note: String = ""            // Original user phrase / context

    init(
        itemID: UUID,
        itemName: String,
        kind: FolioKind,
        operation: Operation,
        delta: Double,
        resultingValue: Double,
        percent: Double? = nil,
        date: Date = .now,
        note: String = ""
    ) {
        self.id             = UUID()
        self.itemID         = itemID
        self.itemName       = itemName
        self.kind           = kind.rawValue
        self.operation      = operation.rawValue
        self.delta          = delta.isFinite ? delta : 0
        self.resultingValue = resultingValue.isFinite ? max(resultingValue, 0) : 0
        self.percent        = percent
        self.date           = date
        self.note           = note
    }

    // MARK: - Typed Accessors

    var folioOperation: Operation {
        Operation(rawValue: operation) ?? .set
    }

    var itemKind: FolioKind {
        FolioKind(rawValue: kind) ?? .asset
    }

    /// Signed effect on net worth: an asset/fund increase is positive, a
    /// liability increase is negative.
    var signedDelta: Double {
        let safe = delta.isFinite ? delta : 0
        return safe * itemKind.netWorthSign
    }
}
