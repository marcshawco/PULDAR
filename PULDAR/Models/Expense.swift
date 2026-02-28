import Foundation
import SwiftData

/// Core SwiftData entity that persists every logged expense.
///
/// `category` and `bucket` are stored as raw `String` values because
/// SwiftData serialises strings natively.  Typed accessors are provided
/// via computed properties.
@Model
final class Expense {
    #Unique<Expense>([\.id])

    var id: UUID
    var merchant: String
    var amount: Double
    var category: String          // Raw LLM category  →  ExpenseCategory
    var bucket: String            // BudgetBucket.rawValue
    var date: Date
    var notes: String             // Original user input preserved

    init(
        merchant: String,
        amount: Double,
        category: String,
        bucket: BudgetBucket,
        date: Date = .now,
        notes: String = ""
    ) {
        self.id       = UUID()
        self.merchant = merchant
        self.amount   = amount
        self.category = category
        self.bucket   = bucket.rawValue
        self.date     = date
        self.notes    = notes
    }

    // MARK: - Typed Accessors

    var budgetBucket: BudgetBucket {
        BudgetBucket(rawValue: bucket) ?? .fun
    }

    var expenseCategory: ExpenseCategory {
        ExpenseCategory.resolve(category)
    }
}
