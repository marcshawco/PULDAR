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

        for (category, keywords) in keywordBank {
            if containsAny(in: normalized, keywords: keywords) {
                return category
            }
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
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static let aliasLookup: [String: ExpenseCategory] = [
        "apartment": .rent,
        "lease": .rent,
        "landlord": .rent,
        "housing": .rent,
        "home loan": .mortgage,
        "property tax": .mortgage,
        "hoa": .mortgage,
        "electric": .utilities,
        "electricity": .utilities,
        "water bill": .utilities,
        "sewer": .utilities,
        "trash": .utilities,
        "garbage": .utilities,
        "power bill": .utilities,
        "gas bill": .utilities,
        "natural gas": .utilities,
        "supermarket": .groceries,
        "market": .groceries,
        "food at home": .groceries,
        "whole foods": .groceries,
        "trader joes": .groceries,
        "costco groceries": .groceries,
        "health insurance": .insurance,
        "car insurance": .insurance,
        "auto insurance": .insurance,
        "renters insurance": .insurance,
        "life insurance": .insurance,
        "doctor": .healthcare,
        "dentist": .healthcare,
        "pharmacy": .healthcare,
        "prescription": .healthcare,
        "urgent care": .healthcare,
        "therapy": .healthcare,
        "uber": .transportation,
        "lyft": .transportation,
        "taxi": .transportation,
        "bus": .transportation,
        "train": .transportation,
        "metro": .transportation,
        "parking": .transportation,
        "toll": .transportation,
        "gas station": .gas,
        "fuel": .gas,
        "mobile phone": .phone,
        "cell phone": .phone,
        "cellphone": .phone,
        "wireless": .phone,
        "wifi": .internet,
        "wi fi": .internet,
        "broadband": .internet,
        "fiber internet": .internet,

        "takeout": .dining,
        "take out": .dining,
        "delivery food": .dining,
        "doordash": .dining,
        "uber eats": .dining,
        "grubhub": .dining,
        "fast food": .dining,
        "coffee shop": .coffee,
        "tea": .coffee,
        "boba": .coffee,
        "starbucks": .coffee,
        "dutch bros": .coffee,
        "netflix": .subscriptions,
        "spotify": .subscriptions,
        "icloud": .subscriptions,
        "gym membership": .subscriptions,
        "membership": .subscriptions,
        "streaming": .subscriptions,
        "clothes": .clothing,
        "shoes": .clothing,
        "apparel": .clothing,
        "wardrobe": .clothing,
        "bookstore": .shopping,
        "retail": .shopping,
        "online shopping": .shopping,
        "amazon": .shopping,
        "target": .shopping,
        "walmart": .shopping,
        "crafts": .hobbies,
        "art supplies": .hobbies,
        "sports gear": .hobbies,
        "concert": .entertainment,
        "movie": .entertainment,
        "cinema": .entertainment,
        "theater": .entertainment,
        "gaming": .entertainment,
        "video game": .entertainment,
        "beer": .alcohol,
        "wine": .alcohol,
        "liquor": .alcohol,
        "bar": .alcohol,
        "present": .gifts,
        "birthday gift": .gifts,
        "holiday gift": .gifts,
        "airfare": .travel,
        "flight": .travel,
        "hotel": .travel,
        "vacation": .travel,

        "emergency fund": .emergency,
        "rainy day fund": .emergency,
        "savings account": .savings,
        "debt payment": .debt,
        "loan payment": .debt,
        "credit card payment": .debt,
        "student loan": .debt,
        "tuition": .education,
        "course": .education,
        "class": .education,
        "school": .education,
        "donation": .charity,
        "donate": .charity,
        "nonprofit": .charity,
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
        "snack bar": .dining,

        "epicerie": .groceries,
        "supermarche": .groceries,
        "courses": .groceries,
        "restaurant": .dining,
        "cafe": .coffee,
        "loyer": .rent,
        "assurance": .insurance,
        "essence": .gas,
        "transport": .transportation,
        "voyage": .travel,
        "abonnements": .subscriptions,
        "epargne": .savings,
        "dette": .debt,
        "investissement": .investments,

        "spesa": .groceries,
        "supermercato": .groceries,
        "ristorante": .dining,
        "affitto": .rent,
        "assicurazione": .insurance,
        "benzina": .gas,
        "trasporto": .transportation,
        "viaggio": .travel,
        "abbonamenti": .subscriptions,
        "risparmio": .savings,
        "debito": .debt,
        "investimenti": .investments,

        "comestibles": .groceries,
        "supermercado": .groceries,
        "restaurante": .dining,
        "alquiler": .rent,
        "seguro": .insurance,
        "gasolina": .gas,
        "transporte": .transportation,
        "viaje": .travel,
        "suscripciones": .subscriptions,
        "ahorro": .savings,
        "deuda": .debt,
        "inversiones": .investments
    ]

    private static let keywordBank: [(ExpenseCategory, [String])] = [
        (.investments, investmentKeywords),
        (.retirement, retirementKeywords),
        (.emergency, emergencyKeywords),
        (.savings, savingsKeywords),
        (.debt, debtKeywords),
        (.education, educationKeywords),
        (.charity, charityKeywords),
        (.rent, rentKeywords),
        (.mortgage, mortgageKeywords),
        (.utilities, utilityKeywords),
        (.insurance, insuranceKeywords),
        (.healthcare, healthcareKeywords),
        (.transportation, transportationKeywords),
        (.gas, gasKeywords),
        (.phone, phoneKeywords),
        (.internet, internetKeywords),
        (.groceries, groceryKeywords),
        (.travel, travelKeywords),
        (.alcohol, alcoholKeywords),
        (.coffee, coffeeKeywords),
        (.entertainment, entertainmentKeywords),
        (.clothing, clothingKeywords),
        (.subscriptions, subscriptionKeywords),
        (.hobbies, hobbyKeywords),
        (.gifts, giftKeywords),
        (.dining, diningKeywords),
        (.shopping, shoppingKeywords)
    ]

    private static let rentKeywords: [String] = [
        "rent", "apartment", "lease", "landlord", "housing", "loyer",
        "affitto", "alquiler"
    ]

    private static let mortgageKeywords: [String] = [
        "mortgage", "home loan", "property tax", "hoa"
    ]

    private static let utilityKeywords: [String] = [
        "utility", "utilities", "electric", "electricity", "water bill",
        "sewer", "trash", "garbage", "power bill", "natural gas", "heat bill"
    ]

    private static let groceryKeywords: [String] = [
        "grocery", "groceries", "supermarket", "market", "food at home",
        "whole foods", "trader joes", "costco groceries", "epicerie",
        "supermarche", "courses", "spesa", "supermercato", "comestibles",
        "supermercado"
    ]

    private static let insuranceKeywords: [String] = [
        "insurance", "premium", "health insurance", "car insurance",
        "auto insurance", "renters insurance", "life insurance",
        "assurance", "assicurazione", "seguro"
    ]

    private static let healthcareKeywords: [String] = [
        "doctor", "dentist", "pharmacy", "prescription", "copay",
        "urgent care", "hospital", "clinic", "therapy", "therapist",
        "medical", "medicine", "healthcare", "vision", "optometrist"
    ]

    private static let transportationKeywords: [String] = [
        "uber", "lyft", "taxi", "bus", "train", "metro", "subway",
        "parking", "toll", "commute", "transit", "transport",
        "transportation", "trasporto", "transporte"
    ]

    private static let gasKeywords: [String] = [
        "gas station", "fuel", "gasoline", "petrol", "essence",
        "benzina", "gasolina"
    ]

    private static let phoneKeywords: [String] = [
        "phone", "cell phone", "cellphone", "mobile phone", "wireless",
        "verizon", "att", "t mobile", "tmobile"
    ]

    private static let internetKeywords: [String] = [
        "internet", "wifi", "wi fi", "broadband", "fiber", "xfinity",
        "spectrum", "cox", "frontier"
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
        "retirement account",
        "dividend",
        "treasury",
        "bond",
        "shares"
    ]

    private static let retirementKeywords: [String] = [
        "retirement", "401k", "403b", "ira", "roth", "pension"
    ]

    private static let emergencyKeywords: [String] = [
        "emergency fund", "rainy day fund"
    ]

    private static let savingsKeywords: [String] = [
        "saving", "savings", "save money", "savings account", "epargne",
        "risparmio", "ahorro"
    ]

    private static let debtKeywords: [String] = [
        "debt", "loan payment", "credit card payment", "student loan",
        "minimum payment", "principal payment", "dette", "debito", "deuda"
    ]

    private static let educationKeywords: [String] = [
        "tuition", "course", "class", "school", "textbook", "books for school",
        "certification", "education"
    ]

    private static let charityKeywords: [String] = [
        "charity", "donation", "donate", "nonprofit", "tithe", "fundraiser"
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
        "amusement park",
        "airbnb",
        "rental car",
        "luggage",
        "passport",
        "voyage",
        "viaggio",
        "viaje"
    ]

    private static let alcoholKeywords: [String] = [
        "alcohol", "beer", "wine", "liquor", "cocktail", "brewery",
        "bar tab", "spirits"
    ]

    private static let coffeeKeywords: [String] = [
        "coffee", "coffee shop", "cafe", "latte", "espresso", "tea",
        "boba", "matcha", "starbucks", "dutch bros"
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
        "show",
        "streaming rental",
        "bowling",
        "karaoke",
        "comedy"
    ]

    private static let clothingKeywords: [String] = [
        "clothing", "clothes", "shoes", "apparel", "wardrobe", "shirt",
        "pants", "dress", "jacket", "sneakers"
    ]

    private static let subscriptionKeywords: [String] = [
        "subscription", "subscriptions", "membership", "netflix", "spotify",
        "hulu", "disney plus", "icloud", "patreon", "gym membership",
        "abonnement", "abonnements", "abbonamento", "abbonamenti",
        "suscripcion", "suscripciones"
    ]

    private static let hobbyKeywords: [String] = [
        "hobby", "hobbies", "craft", "crafts", "art supplies",
        "sports gear", "music gear", "camera gear", "garden", "gardening"
    ]

    private static let giftKeywords: [String] = [
        "gift", "gifts", "present", "birthday gift", "holiday gift",
        "wedding gift", "regalo", "cadeau"
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
        "dessert",
        "ice cream",
        "treat",
        "treats",
        "restaurant",
        "restaurante",
        "ristorante",
        "cena",
        "almuerzo",
        "desayuno",
        "dejeuner",
        "diner",
        "petit dejeuner",
        "colazione",
        "pranzo"
    ]

    private static let shoppingKeywords: [String] = [
        "shopping",
        "mall",
        "retail",
        "bookstore",
        "amazon",
        "target",
        "walmart",
        "online order",
        "department store"
    ]
}
