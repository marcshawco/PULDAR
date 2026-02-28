import Foundation

/// Metered paywall gate — tracks free inputs per week.
///
/// The counter resets automatically every **Sunday at midnight** (local time).
/// Pro users bypass this entirely via `StoreKitManager.isPro`.
///
/// Uses `UserDefaults` with `didSet` (not `@AppStorage`) so that
/// `@Observable` can track mutations and SwiftUI views refresh correctly.
@Observable
final class UsageTracker {

    // MARK: - Persisted Counters

    private var inputCount: Int = UserDefaults.standard.integer(forKey: "weeklyInputCount") {
        didSet { UserDefaults.standard.set(inputCount, forKey: "weeklyInputCount") }
    }

    private var resetTimestamp: Double = UserDefaults.standard.double(forKey: "weekResetTimestamp") {
        didSet { UserDefaults.standard.set(resetTimestamp, forKey: "weekResetTimestamp") }
    }

    // MARK: - Limits

    private let freeLimit = AppConstants.freeInputsPerWeek

    // MARK: - Public API

    /// How many free entries remain this week (clamped ≥ 0).
    var remainingFreeInputs: Int {
        resetIfNeeded()
        return max(freeLimit - inputCount, 0)
    }

    /// `true` when the user has exhausted their free tier.
    var isAtLimit: Bool {
        resetIfNeeded()
        return inputCount >= freeLimit
    }

    /// Current usage count this week.
    var currentCount: Int {
        resetIfNeeded()
        return inputCount
    }

    /// Record one input event.
    func recordInput() {
        resetIfNeeded()
        inputCount += 1
    }

    // MARK: - Auto-Reset Logic

    private func resetIfNeeded() {
        let now = Date()
        let resetDate = Date(timeIntervalSince1970: resetTimestamp)

        if resetTimestamp == 0 || now >= resetDate {
            inputCount = 0
            resetTimestamp = Self.nextSundayMidnight().timeIntervalSince1970
        }
    }

    /// Find the next Sunday at 00:00:00 in the user's local calendar.
    private static func nextSundayMidnight() -> Date {
        let calendar = Calendar.current
        let now = Date()

        // Walk forward day-by-day until we hit Sunday.
        var candidate = calendar.startOfDay(for: now)
        // Advance at least to tomorrow so "now == Sunday 00:00" still rolls forward.
        candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!

        while calendar.component(.weekday, from: candidate) != 1 { // 1 == Sunday
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
        }
        return candidate
    }
}
