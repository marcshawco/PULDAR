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
        didSet {
            let sanitized = monthlyIncome.isFinite ? max(monthlyIncome, 0) : 0
            if sanitized != monthlyIncome {
                monthlyIncome = sanitized
                return
            }
            UserDefaults.standard.set(monthlyIncome, forKey: "monthlyIncome")
        }
    }

    var rolloverEnabled: Bool = UserDefaults.standard.bool(forKey: "rolloverEnabled") {
        didSet {
            UserDefaults.standard.set(rolloverEnabled, forKey: "rolloverEnabled")
        }
    }

    /// Persisted bucket percentages keyed by `BudgetBucket.rawValue`.
    var bucketPercentages: [String: Double] {
        didSet { Self.saveBucketPercentages(bucketPercentages) }
    }

    init() {
        bucketPercentages = Self.loadBucketPercentages()
    }

    // MARK: - Bucket Status

    /// Snapshot of a single bucket's financial state for the current month.
    struct BucketStatus: Identifiable {
        let bucket: BudgetBucket
        let budgeted: Double
        let spent: Double

        var remaining: Double {
            let value = budgeted - spent
            return value.isFinite ? value : 0
        }
        var isOverspent: Bool {
            guard budgeted.isFinite, spent.isFinite else { return false }
            return spent > budgeted
        }
        var progress: Double {
            guard budgeted.isFinite, spent.isFinite, budgeted > 0 else { return 0 }
            return max(0, min(spent / budgeted, 1.5))
        }
        var id: String          { bucket.id }
    }

    // MARK: - Public API

    /// Budget allocated to a single bucket this month.
    func bucketBudget(for bucket: BudgetBucket) -> Double {
        bucketBudget(for: bucket, monthIncome: monthlyIncome)
    }

    /// Budget allocated to a single bucket for a provided month income.
    func bucketBudget(for bucket: BudgetBucket, monthIncome: Double) -> Double {
        let income = monthlyIncome.isFinite ? max(monthlyIncome, 0) : 0
        let safeMonthIncome = monthIncome.isFinite ? max(monthIncome, 0) : income
        let budget = safeMonthIncome * percentage(for: bucket)
        return budget.isFinite ? budget : 0
    }

    func monthSpendCapacity(
        expenses: [Expense],
        recurringExpenses: [RecurringExpense] = [],
        for month: Date = .now
    ) -> Double {
        let base = effectiveMonthlyIncome(expenses: expenses, for: month)
        guard rolloverEnabled else { return base }
        return base + totalRolloverCarryover(
            expenses: expenses,
            recurringExpenses: recurringExpenses,
            for: month
        )
    }

    /// Current percentage (0...1) configured for a bucket.
    func percentage(for bucket: BudgetBucket) -> Double {
        clamp(bucketPercentages[bucket.rawValue] ?? bucket.defaultPercentage)
    }

    /// Update percentage (0...1) for a bucket.
    func setPercentage(_ value: Double, for bucket: BudgetBucket) {
        bucketPercentages[bucket.rawValue] = clamp(value)
    }

    /// Replace all bucket percentages at once.
    func setPercentages(_ values: [String: Double]) {
        var merged: [String: Double] = [:]
        for bucket in BudgetBucket.allCases {
            merged[bucket.rawValue] = clamp(values[bucket.rawValue] ?? percentage(for: bucket))
        }
        bucketPercentages = merged
    }

    /// Sum of all configured percentages.
    var totalPercentage: Double {
        BudgetBucket.allCases.reduce(0) { $0 + percentage(for: $1) }
    }

    /// Amount spent above monthly income for the month.
    func monthlyOverspentAmount(
        expenses: [Expense],
        recurringExpenses: [RecurringExpense] = [],
        for month: Date = .now
    ) -> Double {
        let capacity = monthSpendCapacity(
            expenses: expenses,
            recurringExpenses: recurringExpenses,
            for: month
        )
        guard capacity > 0 else { return 0 }
        return max(
            totalSpent(
                expenses: expenses,
                recurringExpenses: recurringExpenses,
                for: month
            ) - capacity,
            0
        )
    }

    /// Total spent across all buckets this month.
    func totalSpent(
        expenses: [Expense],
        recurringExpenses: [RecurringExpense] = [],
        for month: Date = .now
    ) -> Double {
        let directSpent = filterToMonth(expenses, month: month)
            .filter { !isIncomeTransaction($0) }
            .reduce(0) { partial, expense in
                partial + (expense.amount.isFinite ? expense.amount : 0)
            }
        let recurringSpent = recurringTotal(recurringExpenses)
        return directSpent + recurringSpent
    }

    /// Build status snapshots for every bucket in the current month.
    func calculateStatus(
        expenses: [Expense],
        recurringExpenses: [RecurringExpense] = [],
        for month: Date = .now
    ) -> [BucketStatus] {
        let monthExpenses = filterToMonth(expenses, month: month)
            .filter { !isIncomeTransaction($0) }
        let effectiveIncome = effectiveMonthlyIncome(expenses: expenses, for: month)
        var spentByBucket: [BudgetBucket: Double] = [:]

        for expense in monthExpenses {
            let safeAmount = expense.amount.isFinite ? expense.amount : 0
            spentByBucket[expense.budgetBucket, default: 0] += safeAmount
        }

        return BudgetBucket.allCases.map { bucket in
            let spent = (spentByBucket[bucket] ?? 0) + recurringTotal(
                recurringExpenses,
                bucket: bucket
            )

            return BucketStatus(
                bucket: bucket,
                budgeted: bucketBudgetWithRollover(
                    for: bucket,
                    monthIncome: effectiveIncome,
                    expenses: expenses,
                    recurringExpenses: recurringExpenses,
                    month: month
                ),
                spent: spent
            )
        }
    }

    /// Base monthly income plus any explicit income transactions in the same month.
    func effectiveMonthlyIncome(
        expenses: [Expense],
        for month: Date = .now
    ) -> Double {
        let base = monthlyIncome.isFinite ? max(monthlyIncome, 0) : 0
        return base + incomeTransactionsTotal(expenses: expenses, for: month)
    }

    func incomeTransactionsTotal(
        expenses: [Expense],
        for month: Date = .now
    ) -> Double {
        filterToMonth(expenses, month: month)
            .filter { isIncomeTransaction($0) }
            .reduce(0) { partial, expense in
                let safe = expense.amount.isFinite ? abs(expense.amount) : 0
                return partial + safe
            }
    }

    func totalRolloverCarryover(
        expenses: [Expense],
        recurringExpenses: [RecurringExpense] = [],
        for month: Date = .now
    ) -> Double {
        rolloverEligibleBuckets.reduce(0) { partial, bucket in
            partial + rolloverCarryover(
                for: bucket,
                expenses: expenses,
                recurringExpenses: recurringExpenses,
                month: month,
                depth: 0
            )
        }
    }

    /// Quick check: is *any* bucket over its allocation?
    func hasAnyOverspend(
        expenses: [Expense],
        recurringExpenses: [RecurringExpense] = []
    ) -> Bool {
        calculateStatus(expenses: expenses, recurringExpenses: recurringExpenses)
            .contains { $0.isOverspent }
    }

    func recurringTotal(
        _ recurringExpenses: [RecurringExpense],
        bucket: BudgetBucket? = nil
    ) -> Double {
        recurringExpenses
            .filter { recurring in
                recurring.isActive && (bucket == nil || recurring.budgetBucket == bucket)
            }
            .reduce(0) { partial, recurring in
                partial + recurring.safeAmount
            }
    }

    // MARK: - Helpers

    private func filterToMonth(_ expenses: [Expense], month: Date) -> [Expense] {
        let calendar = Calendar.current
        return expenses.filter {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }

    private func isIncomeTransaction(_ expense: Expense) -> Bool {
        normalize(expense.category) == "income"
    }

    private let rolloverEligibleBuckets: [BudgetBucket] = [.fundamentals, .fun]

    private func bucketBudgetWithRollover(
        for bucket: BudgetBucket,
        monthIncome: Double,
        expenses: [Expense],
        recurringExpenses: [RecurringExpense],
        month: Date
    ) -> Double {
        let base = bucketBudget(for: bucket, monthIncome: monthIncome)
        guard rolloverEnabled, rolloverEligibleBuckets.contains(bucket) else { return base }
        let carry = rolloverCarryover(
            for: bucket,
            expenses: expenses,
            recurringExpenses: recurringExpenses,
            month: month,
            depth: 0
        )
        return base + carry
    }

    private func rolloverCarryover(
        for bucket: BudgetBucket,
        expenses: [Expense],
        recurringExpenses: [RecurringExpense],
        month: Date,
        depth: Int
    ) -> Double {
        guard rolloverEnabled else { return 0 }
        guard rolloverEligibleBuckets.contains(bucket) else { return 0 }
        guard depth < 24 else { return 0 }

        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: month) else {
            return 0
        }

        let prevIncome = effectiveMonthlyIncome(expenses: expenses, for: previousMonth)
        let prevBaseBudget = bucketBudget(for: bucket, monthIncome: prevIncome)
        let prevCarry = rolloverCarryover(
            for: bucket,
            expenses: expenses,
            recurringExpenses: recurringExpenses,
            month: previousMonth,
            depth: depth + 1
        )
        let prevBudgetTotal = prevBaseBudget + prevCarry
        let prevSpent = spentForBucket(
            bucket,
            expenses: expenses,
            recurringExpenses: recurringExpenses,
            month: previousMonth
        )

        return max(prevBudgetTotal - prevSpent, 0)
    }

    private func spentForBucket(
        _ bucket: BudgetBucket,
        expenses: [Expense],
        recurringExpenses: [RecurringExpense],
        month: Date
    ) -> Double {
        let monthSpent = filterToMonth(expenses, month: month)
            .filter { !isIncomeTransaction($0) && $0.budgetBucket == bucket }
            .reduce(0) { $0 + ($1.amount.isFinite ? $1.amount : 0) }
        return monthSpent + recurringTotal(recurringExpenses, bucket: bucket)
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static let bucketPercentageKey = "bucketPercentages"

    private static func loadBucketPercentages() -> [String: Double] {
        var defaults: [String: Double] = [:]
        for bucket in BudgetBucket.allCases {
            defaults[bucket.rawValue] = bucket.defaultPercentage
        }

        if let data = UserDefaults.standard.data(forKey: bucketPercentageKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            var merged = defaults
            for bucket in BudgetBucket.allCases {
                if let value = decoded[bucket.rawValue] {
                    merged[bucket.rawValue] = value.isFinite ? min(max(value, 0), 1) : bucket.defaultPercentage
                }
            }
            return merged
        }
        return defaults
    }

    private static func saveBucketPercentages(_ values: [String: Double]) {
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: bucketPercentageKey)
        }
    }
}
