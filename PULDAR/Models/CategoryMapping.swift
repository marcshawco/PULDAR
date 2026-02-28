import Foundation

/// Every category the LLM is allowed to return, mapped to a budget bucket.
enum ExpenseCategory: String, Codable, CaseIterable {

    // ── Fundamentals (50 %) ────────────────────────────────────────────
    case rent, mortgage, utilities, groceries, insurance
    case healthcare, transportation, gas, phone, internet

    // ── Fun (30 %) ─────────────────────────────────────────────────────
    case dining, entertainment, shopping, clothing, subscriptions
    case hobbies, travel, coffee, alcohol, gifts

    // ── Future You (20 %) ──────────────────────────────────────────────
    case savings, investments, retirement, debt, education
    case emergency, charity

    // ── Fallback ───────────────────────────────────────────────────────
    case other

    /// Deterministic mapping — ALL math lives in Swift, never in the LLM.
    var bucket: BudgetBucket {
        switch self {
        case .rent, .mortgage, .utilities, .groceries, .insurance,
             .healthcare, .transportation, .gas, .phone, .internet:
            return .fundamentals

        case .dining, .entertainment, .shopping, .clothing,
             .subscriptions, .hobbies, .travel, .coffee, .alcohol, .gifts:
            return .fun

        case .savings, .investments, .retirement, .debt,
             .education, .emergency, .charity:
            return .future

        case .other:
            return .fun   // Default uncategorised to "wants"
        }
    }

    /// Resolve any raw string the LLM returns (case-insensitive, trimmed).
    static func resolve(_ raw: String) -> ExpenseCategory {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ExpenseCategory(rawValue: key) ?? .other
    }
}
