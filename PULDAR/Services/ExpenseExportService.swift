import Foundation

@MainActor
enum ExpenseExportService {
    static func writeExpenseCSV(
        expenses: [Expense],
        scope: String,
        categoryDisplayName: (String) -> String
    ) throws -> URL {
        let formatter = ISO8601DateFormatter()
        var csv = "date,merchant,amount,category,bucket,isOverspent,notes\n"

        for expense in sortedExpenses(expenses) {
            let row = [
                csvEscape(formatter.string(from: expense.date)),
                csvEscape(expense.merchant),
                csvEscape(String(format: "%.2f", safeAmount(expense.amount))),
                csvEscape(categoryDisplayName(expense.category)),
                csvEscape(expense.bucket),
                csvEscape(expense.isOverspent ? "true" : "false"),
                csvEscape(expense.notes)
            ].joined(separator: ",")
            csv += row + "\n"
        }

        let url = temporaryURL(prefix: "puldar", scope: scope, fileExtension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func sortedExpenses(_ expenses: [Expense]) -> [Expense] {
        expenses.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.merchant.localizedCaseInsensitiveCompare(rhs.merchant) == .orderedAscending
            }
            return lhs.date > rhs.date
        }
    }

    private static func safeAmount(_ amount: Double) -> Double {
        amount.isFinite ? amount : 0
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func temporaryURL(prefix: String, scope: String, fileExtension: String) -> URL {
        let safeScope = scope
            .replacingOccurrences(of: "[^a-zA-Z0-9_]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
        let scopeComponent = safeScope.isEmpty ? "export" : safeScope
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(scopeComponent).\(fileExtension)")
    }
}
