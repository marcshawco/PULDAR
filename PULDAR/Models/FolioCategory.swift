import Foundation

/// Every Folio item category, grouped into the three balance-sheet kinds.
///
/// Mirrors `ExpenseCategory`: a raw-value enum with deterministic
/// `resolve(_:)` / `keywordCategory(in:)` so the LLM's free-text output maps
/// to a canonical category in Swift (never in the model).
enum FolioCategory: String, Codable, CaseIterable {
    // ── Liabilities ───────────────────────────────────────────────
    case studentLoan   = "student_loan"
    case privateLoan   = "private_loan"
    case carLoan       = "car_loan"
    case personalLoan  = "personal_loan"
    case medicalLoan   = "medical_loan"
    case creditCard    = "credit_card"

    // ── Assets ────────────────────────────────────────────────────
    case vehicle
    case property
    case collectibles
    case stocks
    case crypto

    // ── Funds ─────────────────────────────────────────────────────
    case savings
    case checking
    case sockDrawer    = "sock_drawer"
    case emergencyFund = "emergency_fund"

    // ── Fallback ──────────────────────────────────────────────────
    case other

    /// The balance-sheet group this category belongs to.
    var kind: FolioKind {
        switch self {
        case .studentLoan, .privateLoan, .carLoan, .personalLoan, .medicalLoan, .creditCard:
            return .liability
        case .vehicle, .property, .collectibles, .stocks, .crypto:
            return .asset
        case .savings, .checking, .sockDrawer, .emergencyFund:
            return .fund
        case .other:
            return .asset   // Safest default for "things I own"
        }
    }

    var displayName: String {
        switch self {
        case .studentLoan:   return "Student Loan"
        case .privateLoan:   return "Private Loan"
        case .carLoan:       return "Car Loan"
        case .personalLoan:  return "Personal Loan"
        case .medicalLoan:   return "Medical Loan"
        case .creditCard:    return "Credit Card"
        case .vehicle:       return "Vehicle"
        case .property:      return "Property"
        case .collectibles:  return "Collectibles"
        case .stocks:        return "Stocks"
        case .crypto:        return "Crypto"
        case .savings:       return "Savings"
        case .checking:      return "Checking"
        case .sockDrawer:    return "Sock Drawer"
        case .emergencyFund: return "Emergency Fund"
        case .other:         return "Other"
        }
    }

    /// Selectable categories for a given kind (used by the edit-sheet pickers),
    /// always ending with `.other`.
    static func categories(for kind: FolioKind) -> [FolioCategory] {
        allCases.filter { $0 != .other && $0.kind == kind } + [.other]
    }

    // MARK: - Resolution

    /// Resolve any raw string the LLM returns (case-insensitive, trimmed).
    static func resolve(_ raw: String) -> FolioCategory {
        let key = normalize(raw)
        guard !key.isEmpty else { return .other }

        if let canonical = canonicalLookup[key] {
            return canonical
        }
        if let alias = aliasLookup[key] {
            return alias
        }
        if let keywordMatch = keywordCategory(in: key) {
            return keywordMatch
        }
        return .other
    }

    /// Deterministic keyword overrides for high-signal net-worth terms.
    static func keywordCategory(in text: String) -> FolioCategory? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }

        for (category, keywords) in keywordBank {
            if keywords.contains(where: { normalized.contains($0) }) {
                return category
            }
        }
        return nil
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Normalised rawValue / displayName → category. Built once.
    private static let canonicalLookup: [String: FolioCategory] = {
        var map: [String: FolioCategory] = [:]
        for category in allCases {
            map[normalize(category.rawValue)] = category
            map[normalize(category.displayName)] = category
        }
        return map
    }()

    private static let aliasLookup: [String: FolioCategory] = [
        // Liabilities
        "student loans": .studentLoan,
        "college loan": .studentLoan,
        "uni loan": .studentLoan,
        "auto loan": .carLoan,
        "vehicle loan": .carLoan,
        "car payment": .carLoan,
        "medical debt": .medicalLoan,
        "medical bill": .medicalLoan,
        "hospital bill": .medicalLoan,
        "doctor bill": .medicalLoan,
        "credit card debt": .creditCard,
        "credit cards": .creditCard,
        "visa": .creditCard,
        "mastercard": .creditCard,
        "amex": .creditCard,
        "discover card": .creditCard,
        "loan": .personalLoan,
        "line of credit": .personalLoan,

        // Assets
        "car": .vehicle,
        "truck": .vehicle,
        "automobile": .vehicle,
        "motorcycle": .vehicle,
        "tesla": .vehicle,
        "boat": .vehicle,
        "house": .property,
        "home": .property,
        "condo": .property,
        "real estate": .property,
        "land": .property,
        "rental property": .property,
        "pokemon cards": .collectibles,
        "pokemon": .collectibles,
        "beanie babies": .collectibles,
        "baseball cards": .collectibles,
        "trading cards": .collectibles,
        "comics": .collectibles,
        "comic books": .collectibles,
        "jewelry": .collectibles,
        "watches": .collectibles,
        "art": .collectibles,
        "stock": .stocks,
        "shares": .stocks,
        "brokerage": .stocks,
        "stock portfolio": .stocks,
        "portfolio": .stocks,
        "etf": .stocks,
        "index fund": .stocks,
        "mutual fund": .stocks,
        "401k": .stocks,
        "roth ira": .stocks,
        "ira": .stocks,
        "s p 500": .stocks,
        "bitcoin": .crypto,
        "btc": .crypto,
        "ethereum": .crypto,
        "eth": .crypto,
        "coinbase": .crypto,
        "cryptocurrency": .crypto,
        "dogecoin": .crypto,
        "solana": .crypto,

        // Funds
        "savings account": .savings,
        "checking account": .checking,
        "chequing": .checking,
        "current account": .checking,
        "cash": .sockDrawer,
        "cash on hand": .sockDrawer,
        "wallet": .sockDrawer,
        "mattress": .sockDrawer,
        "petty cash": .sockDrawer,
        "rainy day": .emergencyFund,
        "rainy day fund": .emergencyFund,
        "emergency savings": .emergencyFund
    ]

    /// Ordered so that liability terms are tested before the asset terms they
    /// embed (e.g. "car loan" matches `carLoan` before `vehicle`'s "car").
    private static let keywordBank: [(FolioCategory, [String])] = [
        (.creditCard,    ["credit card", "visa", "mastercard", "amex", "discover card"]),
        (.studentLoan,   ["student loan", "student debt", "college loan"]),
        (.carLoan,       ["car loan", "auto loan", "vehicle loan", "car payment"]),
        (.medicalLoan,   ["medical loan", "medical debt", "medical bill", "hospital bill"]),
        (.personalLoan,  ["personal loan", "line of credit"]),
        (.privateLoan,   ["private loan"]),
        (.crypto,        ["crypto", "bitcoin", "btc", "ethereum", "eth", "coinbase", "dogecoin", "solana"]),
        (.stocks,        ["stock", "shares", "brokerage", "etf", "index fund", "mutual fund", "401k", "roth", "ira", "portfolio", "equities", "s p 500"]),
        (.collectibles,  ["pokemon", "beanie", "trading card", "baseball card", "comic", "collectible", "jewelry", "watch", "art collection"]),
        (.property,      ["house", "home", "condo", "real estate", "property", "land", "duplex"]),
        (.vehicle,       ["car", "truck", "motorcycle", "vehicle", "tesla", "automobile", "boat"]),
        (.emergencyFund, ["emergency fund", "rainy day"]),
        (.savings,       ["savings", "save money"]),
        (.checking,      ["checking", "chequing"]),
        (.sockDrawer,    ["sock drawer", "cash on hand", "petty cash", "mattress", "wallet", "cash"])
    ]
}
