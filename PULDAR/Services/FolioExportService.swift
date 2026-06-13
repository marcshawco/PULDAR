import Foundation

/// CSV / JSON export for Folio items and the net-worth ledger.
///
/// Mirrors `ExpenseExportService`: a `@MainActor enum` of `nonisolated`
/// builders that write to the temporary directory and return a `URL` suitable
/// for `ShareLink`.
@MainActor
enum FolioExportService {
    struct ItemRow: Sendable {
        let name: String
        let kind: String
        let category: String
        let currentValue: Double
        let notes: String
        let createdAt: Date
        let updatedAt: Date?
    }

    struct LedgerRow: Sendable {
        let date: Date
        let itemName: String
        let kind: String
        let operation: String
        let delta: Double
        let resultingValue: Double
        let percent: Double?
        let note: String
    }

    // MARK: - Builders

    static func writeItemsCSV(items: [FolioItem], scope: String = "items") throws -> URL {
        let rows = items.map { item in
            ItemRow(
                name: item.name,
                kind: item.itemKind.rawValue,
                category: item.folioCategory.displayName,
                currentValue: item.currentValue,
                notes: item.notes,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
        }
        return try writeItemsCSV(rows: rows, scope: scope)
    }

    static func writeLedgerCSV(entries: [FolioEntry], scope: String = "ledger") throws -> URL {
        let rows = entries.map { entry in
            LedgerRow(
                date: entry.date,
                itemName: entry.itemName,
                kind: entry.itemKind.rawValue,
                operation: entry.folioOperation.rawValue,
                delta: entry.delta,
                resultingValue: entry.resultingValue,
                percent: entry.percent,
                note: entry.note
            )
        }
        return try writeLedgerCSV(rows: rows, scope: scope)
    }

    static func writeFolioJSON(items: [FolioItem], entries: [FolioEntry]) throws -> URL {
        let snapshot = ExportSnapshot(
            exportedAt: .now,
            netWorth: items.reduce(0) { $0 + $1.signedNetWorthValue },
            items: items.map { item in
                ExportSnapshot.Item(
                    name: item.name,
                    kind: item.itemKind.rawValue,
                    category: item.folioCategory.rawValue,
                    currentValue: safeAmount(item.currentValue),
                    notes: item.notes,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            },
            ledger: entries
                .sorted { $0.date > $1.date }
                .map { entry in
                    ExportSnapshot.LedgerEntry(
                        date: entry.date,
                        itemName: entry.itemName,
                        kind: entry.itemKind.rawValue,
                        operation: entry.folioOperation.rawValue,
                        delta: safeAmount(entry.delta),
                        resultingValue: safeAmount(entry.resultingValue),
                        percent: entry.percent,
                        note: entry.note
                    )
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let url = temporaryURL(prefix: "puldar_folio", scope: "backup", fileExtension: "json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - CSV

    nonisolated static func writeItemsCSV(rows: [ItemRow], scope: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        var csv = "name,kind,category,currentValue,notes,createdAt,updatedAt\n"

        let sorted = rows.sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.kind < rhs.kind
        }

        for row in sorted {
            let line = [
                csvEscape(row.name),
                csvEscape(row.kind),
                csvEscape(row.category),
                csvEscape(String(format: "%.2f", safeAmount(row.currentValue))),
                csvEscape(row.notes),
                csvEscape(formatter.string(from: row.createdAt)),
                csvEscape(row.updatedAt.map { formatter.string(from: $0) } ?? "")
            ].joined(separator: ",")
            csv += line + "\n"
        }

        let url = temporaryURL(prefix: "puldar_folio", scope: scope, fileExtension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated static func writeLedgerCSV(rows: [LedgerRow], scope: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        var csv = "date,itemName,kind,operation,delta,resultingValue,percent,note\n"

        for row in rows.sorted(by: { $0.date > $1.date }) {
            let line = [
                csvEscape(formatter.string(from: row.date)),
                csvEscape(row.itemName),
                csvEscape(row.kind),
                csvEscape(row.operation),
                csvEscape(String(format: "%.2f", safeAmount(row.delta))),
                csvEscape(String(format: "%.2f", safeAmount(row.resultingValue))),
                csvEscape(row.percent.map { String(format: "%.2f", safeAmount($0)) } ?? ""),
                csvEscape(row.note)
            ].joined(separator: ",")
            csv += line + "\n"
        }

        let url = temporaryURL(prefix: "puldar_folio", scope: scope, fileExtension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - JSON Snapshot

    private struct ExportSnapshot: Codable {
        struct Item: Codable {
            let name: String
            let kind: String
            let category: String
            let currentValue: Double
            let notes: String
            let createdAt: Date
            let updatedAt: Date?
        }

        struct LedgerEntry: Codable {
            let date: Date
            let itemName: String
            let kind: String
            let operation: String
            let delta: Double
            let resultingValue: Double
            let percent: Double?
            let note: String
        }

        let exportedAt: Date
        let netWorth: Double
        let items: [Item]
        let ledger: [LedgerEntry]
    }

    // MARK: - Helpers

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
