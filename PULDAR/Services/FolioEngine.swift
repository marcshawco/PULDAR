import Foundation
import SwiftData

/// Pure-Swift net-worth engine for the Folio section.
///
/// ALL math — net worth, group subtotals, allocation, the net-worth-over-time
/// series, and applying parsed AI commands — lives here.  The LLM never does
/// arithmetic (same rule as `BudgetEngine`).
///
/// Unlike `BudgetEngine`, Folio keeps no synced settings: every piece of state
/// is SwiftData (`FolioItem` + `FolioEntry`), so there is no
/// `NSUbiquitousKeyValueStore` machinery here.
@Observable
@MainActor
final class FolioEngine {

    /// Subtotal for one balance-sheet group.
    struct GroupSummary: Identifiable {
        let kind: FolioKind
        let total: Double          // Sum of item magnitudes in this group
        let itemCount: Int
        var id: String { kind.rawValue }
    }

    /// One point on the net-worth-over-time line.
    struct NetWorthPoint: Identifiable {
        let date: Date
        let netWorth: Double
        var id: Date { date }
    }

    /// Outcome of applying a parsed AI command.
    enum ApplyResult {
        case created(FolioItem)
        case updated(FolioItem)
        case failed(String)

        var item: FolioItem? {
            switch self {
            case .created(let item), .updated(let item): return item
            case .failed: return nil
            }
        }

        var isSuccess: Bool { item != nil }
    }

    private var dataRevision: UInt64 = 0
    private var seriesCache: [Int: [NetWorthPoint]] = [:]
    private let maxCacheEntries = 16

    init() {}

    // MARK: - Net Worth Math

    /// Net Worth = Assets + Funds − Liabilities.
    func netWorth(items: [FolioItem]) -> Double {
        items.reduce(0) { $0 + $1.signedNetWorthValue }
    }

    /// Sum of item magnitudes for one group.
    func total(for kind: FolioKind, items: [FolioItem]) -> Double {
        items
            .filter { $0.itemKind == kind }
            .reduce(0) { $0 + FolioItem.sanitize($1.currentValue) }
    }

    /// Items belonging to one group.
    func items(of kind: FolioKind, in items: [FolioItem]) -> [FolioItem] {
        items.filter { $0.itemKind == kind }
    }

    /// Per-group summaries in a stable order (assets, funds, liabilities).
    func groupSummaries(items: [FolioItem]) -> [GroupSummary] {
        FolioKind.allCases.map { kind in
            let group = items.filter { $0.itemKind == kind }
            return GroupSummary(
                kind: kind,
                total: group.reduce(0) { $0 + FolioItem.sanitize($1.currentValue) },
                itemCount: group.count
            )
        }
    }

    /// Non-empty group magnitudes for the breakdown donut.
    func allocationSlices(items: [FolioItem]) -> [GroupSummary] {
        groupSummaries(items: items).filter { $0.total > 0 }
    }

    /// Running net worth over time, derived from the ledger.
    ///
    /// Each point is the cumulative sum of every entry's `signedDelta` up to
    /// and including that entry's date — so the series telescopes to the
    /// current net worth.
    func netWorthSeries(entries: [FolioEntry]) -> [NetWorthPoint] {
        let fingerprint = entriesFingerprint(entries)
        if let cached = seriesCache[fingerprint] {
            return cached
        }

        let sorted = entries.sorted { $0.date < $1.date }
        var running: Double = 0
        var points: [NetWorthPoint] = []
        points.reserveCapacity(sorted.count)
        for entry in sorted {
            running += entry.signedDelta
            points.append(NetWorthPoint(date: entry.date, netWorth: running))
        }

        seriesCache[fingerprint] = points
        trimSeriesCache()
        return points
    }

    /// Bump when SwiftData arrays change to invalidate cached series.
    func markDataChanged() {
        dataRevision &+= 1
        seriesCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Apply AI Command

    /// Apply a parsed Folio command: match an existing item (or create one),
    /// compute the new value in Swift, append a ledger entry, and persist.
    @discardableResult
    func apply(
        command: FolioCommandResult,
        to items: [FolioItem],
        in context: ModelContext,
        originalInput: String
    ) -> ApplyResult {
        let kind = command.folioKind
        let operation = command.folioOperation

        if let match = findItem(for: command, in: items) {
            return applyToExisting(
                match,
                command: command,
                operation: operation,
                in: context,
                originalInput: originalInput
            )
        }

        // No existing item — create one when we have enough to do so.
        return createFromCommand(
            command,
            kind: kind,
            operation: operation,
            in: context,
            originalInput: originalInput
        )
    }

    /// Create or update an item from the manual edit sheet, logging a ledger
    /// entry so the trend and history stay consistent.
    @discardableResult
    func upsertItem(
        existing: FolioItem?,
        name: String,
        kind: FolioKind,
        category: FolioCategory,
        value: Double,
        notes: String,
        in context: ModelContext
    ) -> FolioItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? category.displayName : trimmedName
        let newValue = FolioItem.sanitize(value)

        if let item = existing {
            let oldValue = FolioItem.sanitize(item.currentValue)
            item.name = resolvedName
            item.kind = kind.rawValue
            item.category = category.rawValue
            item.currentValue = newValue
            item.notes = notes
            item.touchUpdatedAt()

            if newValue != oldValue {
                recordEntry(
                    for: item,
                    operation: .set,
                    delta: newValue - oldValue,
                    resultingValue: newValue,
                    percent: nil,
                    note: "Edited",
                    in: context
                )
            }
            save(context, action: "folio.item.edit", metadata: ["name": resolvedName])
            return item
        }

        let item = FolioItem(
            name: resolvedName,
            kind: kind,
            category: category,
            currentValue: newValue,
            notes: notes
        )
        context.insert(item)
        recordEntry(
            for: item,
            operation: .create,
            delta: newValue,
            resultingValue: newValue,
            percent: nil,
            note: "Added manually",
            in: context
        )
        save(context, action: "folio.item.create", metadata: ["name": resolvedName])
        return item
    }

    /// Delete an item, logging a closing entry so the net-worth trend reflects
    /// the drop.  The item's prior ledger entries are kept for history.
    func deleteItem(_ item: FolioItem, in context: ModelContext) {
        let oldValue = FolioItem.sanitize(item.currentValue)
        if oldValue != 0 {
            recordEntry(
                for: item,
                operation: .set,
                delta: -oldValue,
                resultingValue: 0,
                percent: nil,
                note: "Removed",
                in: context
            )
        }
        context.delete(item)
        save(context, action: "folio.item.delete", metadata: ["name": item.name])
    }

    // MARK: - Apply Helpers

    private func applyToExisting(
        _ item: FolioItem,
        command: FolioCommandResult,
        operation: FolioOperation,
        in context: ModelContext,
        originalInput: String
    ) -> ApplyResult {
        let oldValue = FolioItem.sanitize(item.currentValue)

        guard let computed = newValue(
            from: oldValue,
            operation: operation,
            amount: command.resolvedAmount,
            percent: command.resolvedPercent
        ) else {
            return .failed(missingNumberMessage(for: operation))
        }

        let newValue = FolioItem.sanitize(computed)
        item.currentValue = newValue
        item.touchUpdatedAt()

        recordEntry(
            for: item,
            operation: ledgerOperation(for: operation),
            delta: newValue - oldValue,
            resultingValue: newValue,
            percent: operation == .percentChange ? command.resolvedPercent : nil,
            note: originalInput,
            in: context
        )
        save(context, action: "folio.apply.update", metadata: [
            "name": item.name,
            "operation": operation.rawValue,
            "resulting": String(format: "%.2f", newValue)
        ])
        return .updated(item)
    }

    private func createFromCommand(
        _ command: FolioCommandResult,
        kind: FolioKind,
        operation: FolioOperation,
        in context: ModelContext,
        originalInput: String
    ) -> ApplyResult {
        // Only create when we can establish a sensible opening value.
        guard let amount = command.resolvedAmount,
              operation == .set || operation == .add else {
            return .failed("Couldn't find \"\(command.resolvedItemName)\" to update.")
        }

        let openingValue = FolioItem.sanitize(amount)
        let item = FolioItem(
            name: command.resolvedItemName,
            kind: kind,
            category: command.folioCategory,
            currentValue: openingValue,
            notes: originalInput
        )
        context.insert(item)
        recordEntry(
            for: item,
            operation: .create,
            delta: openingValue,
            resultingValue: openingValue,
            percent: nil,
            note: originalInput,
            in: context
        )
        save(context, action: "folio.apply.create", metadata: [
            "name": item.name,
            "kind": kind.rawValue,
            "resulting": String(format: "%.2f", openingValue)
        ])
        return .created(item)
    }

    /// Compute the new magnitude for an operation. Returns nil when the
    /// required number is missing.
    private func newValue(
        from old: Double,
        operation: FolioOperation,
        amount: Double?,
        percent: Double?
    ) -> Double? {
        switch operation {
        case .add:
            guard let amount else { return nil }
            return old + amount
        case .subtract:
            guard let amount else { return nil }
            return max(old - amount, 0)
        case .set:
            guard let amount else { return nil }
            return amount
        case .percentChange:
            guard let percent else { return nil }
            return old * (1 + percent / 100)
        }
    }

    private func ledgerOperation(for operation: FolioOperation) -> FolioEntry.Operation {
        switch operation {
        case .add:           return .add
        case .subtract:      return .subtract
        case .set:           return .set
        case .percentChange: return .percentChange
        }
    }

    private func missingNumberMessage(for operation: FolioOperation) -> String {
        operation == .percentChange
            ? "I couldn't find a percentage in that."
            : "I couldn't find an amount in that."
    }

    // MARK: - Matching

    /// Find the best existing item for a command, restricted to the command's
    /// kind so "car" (asset) and "car loan" (liability) never collide.
    private func findItem(for command: FolioCommandResult, in items: [FolioItem]) -> FolioItem? {
        let candidates = items.filter { $0.itemKind == command.folioKind }
        guard !candidates.isEmpty else { return nil }

        let targetName = CategoryManager.normalize(command.itemName)
        let targetCategory = command.folioCategory

        let scored = candidates
            .map { item -> (item: FolioItem, score: Int) in
                (item, matchScore(item: item, targetName: targetName, targetCategory: targetCategory))
            }
            .filter { $0.score > 0 }

        guard !scored.isEmpty else { return nil }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return recency(of: lhs.item) > recency(of: rhs.item)
            }
            .first?
            .item
    }

    private func matchScore(item: FolioItem, targetName: String, targetCategory: FolioCategory) -> Int {
        let itemName = CategoryManager.normalize(item.name)
        var score = 0

        if !targetName.isEmpty {
            if itemName == targetName {
                score += 100
            } else if itemName.contains(targetName) || targetName.contains(itemName) {
                score += 60
            }
        }

        if targetCategory != .other, item.folioCategory == targetCategory {
            score += 40
        }

        return score
    }

    private func recency(of item: FolioItem) -> Date {
        item.updatedAt ?? item.createdAt
    }

    // MARK: - Persistence

    private func recordEntry(
        for item: FolioItem,
        operation: FolioEntry.Operation,
        delta: Double,
        resultingValue: Double,
        percent: Double?,
        note: String,
        in context: ModelContext
    ) {
        let entry = FolioEntry(
            itemID: item.id,
            itemName: item.name,
            kind: item.itemKind,
            operation: operation,
            delta: delta,
            resultingValue: resultingValue,
            percent: percent,
            note: note
        )
        context.insert(entry)
    }

    private func save(_ context: ModelContext, action: String, metadata: [String: String]) {
        do {
            try context.save()
            markDataChanged()
            DiagnosticLogger.shared.record(
                category: action,
                message: "Folio change saved",
                metadata: metadata
            )
        } catch {
            DiagnosticLogger.shared.record(
                level: .error,
                category: action,
                message: "Failed to save Folio change",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    // MARK: - Cache

    private func entriesFingerprint(_ entries: [FolioEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(dataRevision)
        hasher.combine(entries.count)
        var latest: Date = .distantPast
        var totalDelta: Double = 0
        for entry in entries {
            if entry.date > latest { latest = entry.date }
            totalDelta += entry.signedDelta
        }
        hasher.combine(latest)
        hasher.combine(totalDelta)
        return hasher.finalize()
    }

    private func trimSeriesCache() {
        guard seriesCache.count > maxCacheEntries else { return }
        let overflow = seriesCache.count - maxCacheEntries
        for key in seriesCache.keys.prefix(overflow) {
            seriesCache.removeValue(forKey: key)
        }
    }
}
