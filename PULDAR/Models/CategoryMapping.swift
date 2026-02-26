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
        let key = normalize(raw)
        guard !key.isEmpty else { return .other }

        if let exact = ExpenseCategory(rawValue: key) {
            return exact
        }

        if let alias = aliasLookup[key] {
            return alias
        }

        if let keywordMatch = keywordCategory(in: key) {
            return keywordMatch
        }

        return .other
    }

    /// Deterministic keyword overrides for high-signal expense terms.
    static func keywordCategory(in text: String) -> ExpenseCategory? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }

        if containsAny(in: normalized, keywords: investmentKeywords) {
            return .investments
        }

        if containsAny(in: normalized, keywords: travelKeywords) {
            return .travel
        }

        if containsAny(in: normalized, keywords: entertainmentKeywords) {
            return .entertainment
        }

        if containsAny(in: normalized, keywords: diningKeywords) {
            return .dining
        }

        if containsAny(in: normalized, keywords: shoppingKeywords) {
            return .shopping
        }

        return nil
    }

    private static func containsAny(in text: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            text.contains(keyword)
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static let aliasLookup: [String: ExpenseCategory] = [
        "btc": .investments,
        "bitcoin": .investments,
        "crypto": .investments,
        "cryptocurrency": .investments,
        "sp500": .investments,
        "s p 500": .investments,
        "s and p 500": .investments,
        "sandp 500": .investments,
        "etf": .investments,
        "index fund": .investments,
        "index funds": .investments,
        "stock": .investments,
        "stocks": .investments,
        "mutual fund": .investments,
        "mutual funds": .investments,
        "401k": .investments,
        "roth ira": .investments,
        "ira": .investments,
        "brokerage": .investments,

        "comic": .entertainment,
        "comic books": .entertainment,
        "comicbook": .entertainment,
        "comicbook shop": .entertainment,
        "comic shop": .entertainment,
        "disney": .travel,
        "disneyland": .travel,
        "disney land": .travel,
        "theme park": .travel,
        "amusement park": .travel,
        "snack": .dining,
        "snacks": .dining,
        "snack shop": .dining,
        "snack bar": .dining
    ]

    private static let investmentKeywords: [String] = [
        "invest",
        "investment",
        "investing",
        "bitcoin",
        "btc",
        "crypto",
        "cryptocurrency",
        "sp500",
        "s p 500",
        "s and p 500",
        "sandp 500",
        "etf",
        "index fund",
        "stock",
        "stocks",
        "mutual fund",
        "brokerage",
        "roth ira",
        "401k",
        "retirement account"
    ]

    private static let travelKeywords: [String] = [
        "travel",
        "trip",
        "flight",
        "airfare",
        "hotel",
        "vacation",
        "disney",
        "disneyland",
        "disney land",
        "theme park",
        "amusement park"
    ]

    private static let entertainmentKeywords: [String] = [
        "comic",
        "comic book",
        "comicbook",
        "movie",
        "cinema",
        "theater",
        "concert",
        "festival",
        "game",
        "gaming",
        "arcade",
        "museum",
        "show"
    ]

    private static let diningKeywords: [String] = [
        "snack",
        "snacks",
        "snack shop",
        "snack bar",
        "restaurant",
        "dinner",
        "lunch",
        "breakfast",
        "pizza",
        "sushi",
        "burger",
        "cafe",
        "coffee",
        "boba",
        "dessert",
        "ice cream",
        "treat",
        "treats"
    ]

    private static let shoppingKeywords: [String] = [
        "shopping",
        "mall",
        "retail",
        "clothes",
        "clothing",
        "shoes",
        "bookstore"
    ]
}
