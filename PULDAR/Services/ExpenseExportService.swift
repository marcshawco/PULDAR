import Foundation

enum ExpenseExportService {
    struct ExpenseRecord: Codable {
        let id: UUID
        let date: Date
        let merchant: String
        let amount: Double
        let category: String
        let bucket: String
        let isOverspent: Bool
        let notes: String
        let source: String
        let externalTransactionID: String?
        let externalAccountID: String?
        let importedAt: Date?
    }

    struct RecurringRecord: Codable {
        let id: UUID
        let name: String
        let amount: Double
        let bucket: String
        let isActive: Bool
        let createdAt: Date
    }

    struct BackupPayload: Codable {
        let createdAt: Date
        let scope: String
        let monthlyIncome: Double
        let percentages: [String: Double]
        let expenses: [ExpenseRecord]
        let recurring: [RecurringRecord]
    }

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

    static func writeExpenseJSON(
        expenses: [Expense],
        scope: String,
        categoryDisplayName: (String) -> String
    ) throws -> URL {
        let payload = sortedExpenses(expenses).map {
            expenseRecord(from: $0, category: categoryDisplayName($0.category))
        }
        let url = temporaryURL(prefix: "puldar", scope: scope, fileExtension: "json")
        try encode(payload).write(to: url, options: .atomic)
        return url
    }

    static func writeBackupJSON(
        expenses: [Expense],
        recurring: [RecurringExpense],
        scope: String,
        monthlyIncome: Double,
        percentages: [String: Double],
        filePrefix: String = "puldar"
    ) throws -> URL {
        let payload = BackupPayload(
            createdAt: .now,
            scope: scope,
            monthlyIncome: safeAmount(monthlyIncome),
            percentages: sanitizePercentages(percentages),
            expenses: sortedExpenses(expenses).map {
                expenseRecord(from: $0, category: $0.category)
            },
            recurring: recurring.sorted { $0.createdAt > $1.createdAt }.map(recurringRecord)
        )
        let url = temporaryURL(prefix: filePrefix, scope: scope, fileExtension: "json")
        try encode(payload).write(to: url, options: .atomic)
        return url
    }

    static func writeFullDeviceBackupJSON(
        expenses: [Expense],
        recurring: [RecurringExpense],
        monthlyIncome: Double,
        percentages: [String: Double]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("puldar_backup_\(Int(Date.now.timeIntervalSince1970)).json")
        let payload = BackupPayload(
            createdAt: .now,
            scope: "full_device_backup",
            monthlyIncome: safeAmount(monthlyIncome),
            percentages: sanitizePercentages(percentages),
            expenses: sortedExpenses(expenses).map {
                expenseRecord(from: $0, category: $0.category)
            },
            recurring: recurring.sorted { $0.createdAt > $1.createdAt }.map(recurringRecord)
        )
        try encode(payload).write(to: url, options: .atomic)
        return url
    }

    private static func expenseRecord(from expense: Expense, category: String) -> ExpenseRecord {
        ExpenseRecord(
            id: expense.id,
            date: expense.date,
            merchant: expense.merchant,
            amount: safeAmount(expense.amount),
            category: category,
            bucket: expense.bucket,
            isOverspent: expense.isOverspent,
            notes: expense.notes,
            source: expense.sourceKind.rawValue,
            externalTransactionID: expense.externalTransactionID,
            externalAccountID: expense.externalAccountID,
            importedAt: expense.importedAt
        )
    }

    private static func recurringRecord(from recurring: RecurringExpense) -> RecurringRecord {
        RecurringRecord(
            id: recurring.id,
            name: recurring.name,
            amount: recurring.safeAmount,
            bucket: recurring.bucket,
            isActive: recurring.isActive,
            createdAt: recurring.createdAt
        )
    }

    private static func sortedExpenses(_ expenses: [Expense]) -> [Expense] {
        expenses.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.merchant.localizedCaseInsensitiveCompare(rhs.merchant) == .orderedAscending
            }
            return lhs.date > rhs.date
        }
    }

    private static func sanitizePercentages(_ percentages: [String: Double]) -> [String: Double] {
        percentages.mapValues { value in
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 1)
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

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
