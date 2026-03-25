import Foundation
import SwiftData

/// Core SwiftData entity that persists every logged expense.
///
/// `category` and `bucket` are stored as raw `String` values because
/// SwiftData serialises strings natively.  Typed accessors are provided
/// via computed properties.
@Model
final class Expense {
    enum SourceKind: String, Codable, CaseIterable {
        case manual
        case receiptScan
        case appleWalletSync
    }

    var id: UUID = UUID()
    var merchant: String = ""
    var amount: Double = 0
    var category: String = ExpenseCategory.other.rawValue          // Raw LLM category  →  ExpenseCategory
    var bucket: String = BudgetBucket.fun.rawValue                 // BudgetBucket.rawValue
    var isOverspent: Bool = false
    var date: Date = Date()
    var notes: String = ""        // Original user input preserved
    var source: String?
    var externalTransactionID: String?
    var externalAccountID: String?
    var importedAt: Date?
    var updatedAt: Date?

    init(
        merchant: String,
        amount: Double,
        category: String,
        bucket: BudgetBucket,
        isOverspent: Bool = false,
        date: Date = .now,
        notes: String = "",
        source: SourceKind = .manual,
        externalTransactionID: String? = nil,
        externalAccountID: String? = nil,
        importedAt: Date? = nil,
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
        self.source = source.rawValue
        self.externalTransactionID = externalTransactionID
        self.externalAccountID = externalAccountID
        self.importedAt = importedAt
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

    var sourceKind: SourceKind {
        SourceKind(rawValue: source ?? "") ?? .manual
    }

    func touchUpdatedAt() {
        updatedAt = .now
    }
}
