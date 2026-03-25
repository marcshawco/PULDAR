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

        let normalized = normalize(fallbackInput)
        let creditSignals = [
            "gave me", "gift", "refund", "reimburs", "cashback", "cash back",
            "found", "increase", "add ", "added ", "credit", "deposit",
            "income", "paid me", "sent me", "received", "got paid",
            "reembolso", "regalo", "deposito", "ingreso", "me pagaron", "recibi",
            "rimborso", "regalo", "deposito", "entrata", "ricevuto",
            "remboursement", "cadeau", "depot", "revenu", "recu"
        ]

        return creditSignals.contains { normalized.contains($0) }
    }

    func isIncome(fallbackInput: String) -> Bool {
        let normalized = normalize(fallbackInput)
        let incomeSignals = [
            "salary", "paycheck", "pay check", "got paid", "paid me",
            "direct deposit", "payroll", "wages", "bonus",
            "freelance", "invoice", "client paid", "income",
            "salario", "nomina", "sueldo", "pago directo", "factura", "ingreso",
            "stipendio", "busta paga", "salario", "bonifico", "fattura", "entrata",
            "salaire", "paie", "depot direct", "facture", "revenu"
        ]
        return incomeSignals.contains { normalized.contains($0) }
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
