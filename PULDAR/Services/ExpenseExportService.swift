import Foundation

@MainActor
enum ExpenseExportService {
    struct ExpenseRow: Sendable {
        let date: Date
        let merchant: String
        let amount: Double
        let categoryDisplay: String
        let bucket: String
        let isOverspent: Bool
        let notes: String
    }

    static func writeExpenseCSV(
        expenses: [Expense],
        scope: String,
        categoryDisplayName: (String) -> String
    ) throws -> URL {
        let rows = expenses.map { expense in
            ExpenseRow(
                date: expense.date,
                merchant: expense.merchant,
                amount: expense.amount,
                categoryDisplay: categoryDisplayName(expense.category),
                bucket: expense.bucket,
                isOverspent: expense.isOverspent,
                notes: expense.notes
            )
        }
        return try writeCSV(rows: rows, scope: scope)
    }

    nonisolated static func writeCSV(rows: [ExpenseRow], scope: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        var csv = "date,merchant,amount,category,bucket,isOverspent,notes\n"

        for row in sortedRows(rows) {
            let line = [
                csvEscape(formatter.string(from: row.date)),
                csvEscape(row.merchant),
                csvEscape(String(format: "%.2f", safeAmount(row.amount))),
                csvEscape(row.categoryDisplay),
                csvEscape(row.bucket),
                csvEscape(row.isOverspent ? "true" : "false"),
                csvEscape(row.notes)
            ].joined(separator: ",")
            csv += line + "\n"
        }

        let url = temporaryURL(prefix: "puldar", scope: scope, fileExtension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated private static func sortedRows(_ rows: [ExpenseRow]) -> [ExpenseRow] {
        rows.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.merchant.localizedCaseInsensitiveCompare(rhs.merchant) == .orderedAscending
            }
            return lhs.date > rhs.date
        }
    }

    nonisolated private static func safeAmount(_ amount: Double) -> Double {
        amount.isFinite ? amount : 0
    }

    nonisolated private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    nonisolated private static func temporaryURL(prefix: String, scope: String, fileExtension: String) -> URL {
        let safeScope = scope
            .replacingOccurrences(of: "[^a-zA-Z0-9_]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
        let scopeComponent = safeScope.isEmpty ? "export" : safeScope
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(scopeComponent).\(fileExtension)")
    }
}
