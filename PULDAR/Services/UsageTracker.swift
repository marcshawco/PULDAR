import Foundation

/// Metered paywall gate — tracks free inputs per month.
///
/// The counter resets automatically at the start of each calendar month (local time).
/// Pro users bypass this entirely via `StoreKitManager.isPro`.
///
/// Uses `UserDefaults` with `didSet` (not `@AppStorage`) so that
/// `@Observable` can track mutations and SwiftUI views refresh correctly.
@Observable
final class UsageTracker {

    // MARK: - Persisted Counters

    private var inputCount: Int = UserDefaults.standard.integer(forKey: "monthlyInputCount") {
        didSet { UserDefaults.standard.set(inputCount, forKey: "monthlyInputCount") }
    }

    private var periodKey: String = UserDefaults.standard.string(forKey: "monthlyUsagePeriodKey") ?? "" {
        didSet { UserDefaults.standard.set(periodKey, forKey: "monthlyUsagePeriodKey") }
    }

    // MARK: - Limits

    private let freeLimit = AppConstants.freeInputsPerMonth

    // MARK: - Public API

    /// How many free entries remain this month (clamped ≥ 0).
    var remainingFreeInputs: Int {
        resetIfNeeded()
        return max(freeLimit - inputCount, 0)
    }

    /// `true` when the user has exhausted their free tier.
    var isAtLimit: Bool {
        resetIfNeeded()
        return inputCount >= freeLimit
    }

    /// Current usage count this month.
    var currentCount: Int {
        resetIfNeeded()
        return inputCount
    }

    /// Record one input event.
    func recordInput() {
        resetIfNeeded()
        inputCount += 1
    }

    /// Keep usage in sync with persisted records for the current month.
    ///
    /// This prevents drift when local defaults survive but SwiftData store
    /// changes (for example after schema updates).
    func reconcile(with expenses: [Expense]) {
        resetIfNeeded()
        let window = Self.currentUsageWindow()
        let count = expenses.filter { $0.date >= window.start && $0.date < window.end }.count
        if count != inputCount {
            inputCount = count
        }
    }

    // MARK: - Auto-Reset Logic

    private func resetIfNeeded() {
        let currentPeriod = Self.currentPeriodKey()

        if periodKey != currentPeriod {
            inputCount = 0
            periodKey = currentPeriod
        }

        // Keep any previous values bounded.
        if inputCount < 0 {
            inputCount = 0
        }
    }

    private static func currentPeriodKey(now: Date = Date()) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: now)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private static func currentUsageWindow() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: 1, to: start)
            ?? now
        return (start, end)
    }
}
