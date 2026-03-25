import Foundation
import Observation
import SwiftData

#if canImport(FinanceKit)
import FinanceKit
#endif

/// FinanceKit readiness and import scaffolding.
///
/// The real Apple authorization flow is entitlement-gated, so this service
/// focuses on:
/// - availability / entitlement gating
/// - user-facing fallback messaging
/// - import deduplication and mapping into `Expense`
@Observable
@MainActor
final class FinanceKitManager {
    enum AvailabilityState: Equatable {
        case checking
        case available
        case unsupportedOS
        case frameworkUnavailable
        case entitlementRequired
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct ImportedTransactionCandidate: Identifiable, Hashable {
        let id: String
        let accountID: String
        let merchant: String
        let amount: Double
        let date: Date
        let notes: String

        init(
            id: String,
            accountID: String,
            merchant: String,
            amount: Double,
            date: Date,
            notes: String = ""
        ) {
            self.id = id
            self.accountID = accountID
            self.merchant = merchant
            self.amount = amount
            self.date = date
            self.notes = notes
        }
    }

    struct ImportPreview: Equatable {
        let newCount: Int
        let duplicateCount: Int
    }

    struct ImportResult: Equatable {
        let importedCount: Int
        let duplicateCount: Int
    }

    private enum StorageKey {
        static let connected = "financeKitConnected"
        static let lastSyncDate = "financeKitLastSyncDate"
        static let lastImportedCount = "financeKitLastImportedCount"
    }

    private let defaults = UserDefaults.standard

    private(set) var availability: AvailabilityState = .checking
    private(set) var isConnected: Bool
    private(set) var lastSyncDate: Date?
    private(set) var lastImportedCount: Int
    private(set) var lastSyncError: String?

    init() {
        isConnected = defaults.bool(forKey: StorageKey.connected)
        lastSyncDate = defaults.object(forKey: StorageKey.lastSyncDate) as? Date
        lastImportedCount = defaults.integer(forKey: StorageKey.lastImportedCount)
        refreshAvailability()
    }

    var statusTitle: String {
        switch availability {
        case .checking:
            return "Checking availability"
        case .available:
            return isConnected ? "Ready to sync" : "Available on this device"
        case .unsupportedOS:
            return "Requires a newer iPhone/iOS"
        case .frameworkUnavailable:
            return "FinanceKit unavailable in this build"
        case .entitlementRequired:
            return "Awaiting Apple approval"
        }
    }

    var detailText: String {
        switch availability {
        case .checking:
            return "PULDAR is checking whether Apple Wallet account sync can be used on this device."
        case .available:
            if isConnected {
                let syncSummary: String
                if let lastSyncDate {
                    syncSummary = "Last sync: \(lastSyncDate.formatted(date: .abbreviated, time: .shortened))."
                } else {
                    syncSummary = "No sync has run yet."
                }
                return "Apple Wallet account import is configured. \(syncSummary) Imports deduplicate by transaction ID so the same purchase does not get added twice."
            }
            return "Apple Wallet account sync can import Apple Card, Apple Cash, and Savings data when FinanceKit is available and approved for this app."
        case .unsupportedOS:
            return "FinanceKit is only available on supported iPhone/iOS versions. Manual entry, receipt scan, and JSON/CSV flows remain available."
        case .frameworkUnavailable:
            return "This build environment does not expose the FinanceKit framework yet. The app keeps working with manual entry, receipt scanning, and exports."
        case .entitlementRequired:
            return "The UX and import pipeline are ready, but Apple still requires the FinanceKit entitlement before live Wallet account authorization can be turned on."
        }
    }

    var primaryActionTitle: String {
        if availability == .available {
            return isConnected ? "Sync Apple Wallet Transactions" : "Connect Apple Wallet Accounts"
        }
        return "Learn About Apple Wallet Sync"
    }

    func refreshAvailability() {
        availability = Self.computeAvailability()
        DiagnosticLogger.shared.record(
            category: "financekit.availability",
            message: "Refreshed FinanceKit availability",
            metadata: ["state": String(describing: availability)]
        )
    }

    func primaryActionNotice() -> Notice {
        switch availability {
        case .available:
            if isConnected {
                return Notice(
                    title: "Sync Ready",
                    message: "The import pipeline is ready to sync Apple Wallet transactions. Finish the live FinanceKit authorization call once the production entitlement is active for this bundle."
                )
            }
            return Notice(
                title: "Connect Apple Wallet Accounts",
                message: "PULDAR is ready for Apple Wallet transaction import UX, deduplication, and local storage. The final authorization call still depends on Apple granting the FinanceKit entitlement for this app."
            )
        case .unsupportedOS:
            return Notice(
                title: "Apple Wallet Sync Unavailable",
                message: "This feature needs a supported iPhone/iOS version. You can still use manual entry, receipt scanning, and CSV/JSON export-import flows."
            )
        case .frameworkUnavailable:
            return Notice(
                title: "FinanceKit Not In This Build",
                message: "The current toolchain cannot import FinanceKit here. The app keeps its manual entry, receipt scanning, and export paths as the fallback."
            )
        case .entitlementRequired:
            return Notice(
                title: "Waiting on FinanceKit Approval",
                message: "Apple Wallet sync is product-ready in PULDAR, but Apple must approve the FinanceKit entitlement before live account connection can ship."
            )
        case .checking:
            return Notice(
                title: "Checking Availability",
                message: "PULDAR is still evaluating whether Apple Wallet sync can be used on this device."
            )
        }
    }

    func previewImport(
        _ candidates: [ImportedTransactionCandidate],
        existingExpenses: [Expense]
    ) -> ImportPreview {
        let existingIDs = Set(existingExpenses.compactMap(\.externalTransactionID))
        let duplicateCount = candidates.filter { existingIDs.contains($0.id) }.count
        return ImportPreview(
            newCount: candidates.count - duplicateCount,
            duplicateCount: duplicateCount
        )
    }

    func importTransactions(
        _ candidates: [ImportedTransactionCandidate],
        into modelContext: ModelContext,
        existingExpenses: [Expense],
        categoryManager: CategoryManager,
        budgetEngine: BudgetEngine
    ) throws -> ImportResult {
        let existingIDs = Set(existingExpenses.compactMap(\.externalTransactionID))

        var importedCount = 0
        var duplicateCount = 0

        for candidate in candidates {
            if existingIDs.contains(candidate.id) {
                duplicateCount += 1
                continue
            }

            let resolved = categoryManager.resolve(
                raw: "uncategorized",
                context: "\(candidate.merchant) \(candidate.notes)"
            )

            let expense = Expense(
                merchant: candidate.merchant.normalizedMerchantName(),
                amount: abs(candidate.amount),
                category: resolved.storageKey,
                bucket: resolved.bucket,
                isOverspent: false,
                date: candidate.date,
                notes: candidate.notes,
                source: .appleWalletSync,
                externalTransactionID: candidate.id,
                externalAccountID: candidate.accountID,
                importedAt: .now,
                updatedAt: .now
            )

            modelContext.insert(expense)
            importedCount += 1
        }

        if importedCount > 0 {
            try modelContext.save()
            budgetEngine.markDataChanged()
            isConnected = true
            lastSyncDate = .now
            lastImportedCount = importedCount
            defaults.set(true, forKey: StorageKey.connected)
            defaults.set(lastSyncDate, forKey: StorageKey.lastSyncDate)
            defaults.set(lastImportedCount, forKey: StorageKey.lastImportedCount)
            lastSyncError = nil
            DiagnosticLogger.shared.record(
                category: "financekit.import",
                message: "Imported Apple Wallet transactions",
                metadata: [
                    "imported": "\(importedCount)",
                    "duplicates": "\(duplicateCount)"
                ]
            )
        }

        return ImportResult(importedCount: importedCount, duplicateCount: duplicateCount)
    }

    func markSyncFailure(_ error: Error) {
        lastSyncError = error.localizedDescription
        DiagnosticLogger.shared.record(
            level: .warning,
            category: "financekit.sync",
            message: "Apple Wallet sync failed",
            metadata: ["error": error.localizedDescription]
        )
    }

    private static func computeAvailability() -> AvailabilityState {
        #if canImport(FinanceKit)
        guard #available(iOS 17.4, *) else {
            return .unsupportedOS
        }
        return hasFinanceKitEntitlement() ? .available : .entitlementRequired
        #else
        return .frameworkUnavailable
        #endif
    }

    private static func hasFinanceKitEntitlement() -> Bool {
        // Keep this conservative in development builds. Live FinanceKit access
        // still depends on Apple granting the entitlement for the signed app.
        return false
    }
}
