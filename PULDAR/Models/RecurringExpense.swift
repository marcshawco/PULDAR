import Foundation
import SwiftData

/// User-defined monthly recurring commitment (e.g. Hulu, Rent, Gym).
///
/// These are applied as monthly budget load in calculations so the user's
/// "available left" reflects fixed commitments at the start of each month.
@Model
final class RecurringExpense {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var amount: Double
    var bucket: String
    var isActive: Bool
    var createdAt: Date

    init(
        name: String,
        amount: Double,
        bucket: BudgetBucket,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.bucket = bucket.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var budgetBucket: BudgetBucket {
        BudgetBucket(rawValue: bucket) ?? .fun
    }

    var safeAmount: Double {
        guard amount.isFinite else { return 0 }
        return max(amount, 0)
    }
}
