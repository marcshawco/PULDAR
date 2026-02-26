import Foundation

enum LLMTransactionType: String, Codable {
    case expense
    case credit
}

/// The strict JSON contract between the local LLM and the app.
///
/// The model is prompted to return exactly:
/// ```json
/// {"merchant": "Store Name", "amount": 12.50, "category": "groceries", "transactionType": "expense"}
/// ```
struct LLMExpenseResult: Codable {
    let merchant: String
    let amount: Double
    let category: String
    let transactionType: LLMTransactionType?

    /// Convert model output into signed amount used by budgets.
    ///
    /// Credits (gifts/refunds/found money/reimbursements) become negative
    /// so they reduce spending in the matched category.
    func signedAmount(fallbackInput: String) -> Double {
        let unsigned = abs(amount)
        if isCredit(fallbackInput: fallbackInput) {
            return -unsigned
        }
        return unsigned
    }

    func isCredit(fallbackInput: String) -> Bool {
        if amount < 0 { return true }
        if transactionType == .credit { return true }

        let normalized = fallbackInput.lowercased()
        let creditSignals = [
            "gave me", "gift", "refund", "reimburs", "cashback", "cash back",
            "found", "increase", "add ", "added ", "credit", "deposit",
            "income", "paid me", "sent me", "received", "got paid"
        ]

        return creditSignals.contains { normalized.contains($0) }
    }
}
