import Foundation
import SwiftUI

/// Pure-Swift budgeting engine.
///
/// ALL math — budget allocation, spend aggregation, overspend detection —
/// lives here.  The LLM never does arithmetic.
///
/// Uses `UserDefaults` with `didSet` (not `@AppStorage`) so that
/// `@Observable` can track mutations and SwiftUI views refresh correctly.
@Observable
@MainActor
final class BudgetEngine {

    // MARK: - Persisted Income

    var monthlyIncome: Double = UserDefaults.standard.double(forKey: "monthlyIncome") {
        didSet { UserDefaults.standard.set(monthlyIncome, forKey: "monthlyIncome") }
    }

    // MARK: - Bucket Status

    /// Snapshot of a single bucket's financial state for the current month.
    struct BucketStatus: Identifiable {
        let bucket: BudgetBucket
        let budgeted: Double
        let spent: Double

        var remaining: Double   { budgeted - spent }
        var isOverspent: Bool   { spent > budgeted }
        var progress: Double    { budgeted > 0 ? min(spent / budgeted, 1.5) : 0 }
        var id: String          { bucket.id }
    }

    // MARK: - Public API

    /// Budget allocated to a single bucket this month.
    func bucketBudget(for bucket: BudgetBucket) -> Double {
        monthlyIncome * bucket.targetPercentage
    }

    /// Total spent across all buckets this month.
    func totalSpent(expenses: [Expense], for month: Date = .now) -> Double {
        filterToMonth(expenses, month: month).reduce(0) { $0 + $1.amount }
    }

    /// Build status snapshots for every bucket in the current month.
    func calculateStatus(
        expenses: [Expense],
        for month: Date = .now
    ) -> [BucketStatus] {
        let monthExpenses = filterToMonth(expenses, month: month)

        return BudgetBucket.allCases.map { bucket in
            let spent = monthExpenses
                .filter { $0.budgetBucket == bucket }
                .reduce(0) { $0 + $1.amount }

            return BucketStatus(
                bucket: bucket,
                budgeted: bucketBudget(for: bucket),
                spent: spent
            )
        }
    }

    /// Quick check: is *any* bucket over its allocation?
    func hasAnyOverspend(expenses: [Expense]) -> Bool {
        calculateStatus(expenses: expenses).contains { $0.isOverspent }
    }

    // MARK: - Helpers

    private func filterToMonth(_ expenses: [Expense], month: Date) -> [Expense] {
        let calendar = Calendar.current
        return expenses.filter {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }
}
