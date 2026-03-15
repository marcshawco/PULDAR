import Foundation
import SwiftData

/// Core SwiftData entity that persists every logged expense.
///
/// `category` and `bucket` are stored as raw `String` values because
/// SwiftData serialises strings natively.  Typed accessors are provided
/// via computed properties.
@Model
final class Expense {
    @Attribute(.unique)
    var id: UUID
    var merchant: String
    var amount: Double
    var category: String          // Raw LLM category  →  ExpenseCategory
    var bucket: String            // BudgetBucket.rawValue
    var isOverspent: Bool = false
    var date: Date
    var notes: String             // Original user input preserved
    var updatedAt: Date?

    init(
        merchant: String,
        amount: Double,
        category: String,
        bucket: BudgetBucket,
        isOverspent: Bool = false,
        date: Date = .now,
        notes: String = "",
        updatedAt: Date? = nil
    ) {
        self.id       = UUID()
        self.merchant = merchant
        self.amount   = amount
        self.category = category
        self.bucket   = bucket.rawValue
        self.isOverspent = isOverspent
        self.date     = date
        self.notes    = notes
        self.updatedAt = updatedAt
    }

    // MARK: - Typed Accessors

    var budgetBucket: BudgetBucket {
        BudgetBucket(rawValue: bucket) ?? .fun
    }

    var expenseCategory: ExpenseCategory {
        ExpenseCategory.resolve(category)
    }

    var normalizedMerchant: String {
        merchant.normalizedMerchantName()
    }

    func touchUpdatedAt() {
        updatedAt = .now
    }
}
