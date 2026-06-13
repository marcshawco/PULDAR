import SwiftUI
import SwiftData

/// The three balance-sheet groups in Folio.
///
/// Net Worth = Assets + Funds − Liabilities.  Assets and funds add to net
/// worth; liabilities subtract.  Item values are always stored as
/// non-negative magnitudes — the sign is derived from the kind.
enum FolioKind: String, Codable, CaseIterable, Identifiable {
    case asset
    case fund
    case liability

    var id: String { rawValue }

    /// Sign applied to `currentValue` when summing net worth.
    var netWorthSign: Double {
        switch self {
        case .asset, .fund: return 1
        case .liability:    return -1
        }
    }

    /// Plural group name shown as a section header.
    var displayName: String {
        switch self {
        case .asset:     return "Assets"
        case .fund:      return "Funds"
        case .liability: return "Liabilities"
        }
    }

    /// Singular noun for buttons and sheets ("Add Asset").
    var singularName: String {
        switch self {
        case .asset:     return "Asset"
        case .fund:      return "Fund"
        case .liability: return "Liability"
        }
    }

    /// Short subtitle describing the group.
    var subtitle: String {
        switch self {
        case .asset:     return "What you own"
        case .fund:      return "Cash you hold"
        case .liability: return "What you owe"
        }
    }

    /// SF Symbol for each group.
    var icon: String {
        switch self {
        case .asset:     return "house"
        case .fund:      return "banknote"
        case .liability: return "creditcard"
        }
    }

    /// Colour mapped from the app palette (reuses the three bucket accents).
    var color: Color {
        switch self {
        case .asset:     return AppColors.bucketFuture
        case .fund:      return AppColors.bucketFun
        case .liability: return AppColors.overspend
        }
    }
}

/// Core SwiftData entity for a single net-worth item (an asset, fund, or
/// liability).
///
/// `kind` and `category` are stored as raw `String` values because SwiftData
/// serialises strings natively.  Typed accessors are provided via computed
/// properties — mirroring `Expense`.  All math (net worth, deltas) lives in
/// `FolioEngine`, never in this model.
@Model
final class FolioItem {
    var id: UUID = UUID()
    var name: String = ""
    var kind: String = FolioKind.asset.rawValue            // FolioKind.rawValue
    var category: String = FolioCategory.other.rawValue    // FolioCategory.rawValue
    var currentValue: Double = 0                           // Always a non-negative magnitude
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date?

    init(
        name: String,
        kind: FolioKind,
        category: FolioCategory = .other,
        currentValue: Double = 0,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id           = UUID()
        self.name         = name
        self.kind         = kind.rawValue
        self.category     = category.rawValue
        self.currentValue = Self.sanitize(currentValue)
        self.notes        = notes
        self.createdAt    = createdAt
        self.updatedAt    = updatedAt
    }

    // MARK: - Typed Accessors

    var itemKind: FolioKind {
        FolioKind(rawValue: kind) ?? .asset
    }

    var folioCategory: FolioCategory {
        FolioCategory.resolve(category)
    }

    /// Signed contribution to net worth (liabilities are negative).
    var signedNetWorthValue: Double {
        Self.sanitize(currentValue) * itemKind.netWorthSign
    }

    func touchUpdatedAt() {
        updatedAt = .now
    }

    /// Clamp to a finite, non-negative magnitude.
    static func sanitize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }
}
