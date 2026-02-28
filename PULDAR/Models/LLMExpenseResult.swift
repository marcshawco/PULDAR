import Foundation

/// The strict JSON contract between the local LLM and the app.
///
/// The model is prompted to return exactly:
/// ```json
/// {"merchant": "Store Name", "amount": 12.50, "category": "groceries"}
/// ```
struct LLMExpenseResult: Codable {
    let merchant: String
    let amount: Double
    let category: String
}
