import AppIntents
import Foundation

// Nonisolated DTO matching the JSON written by WidgetBudgetSnapshotStore.
private struct BudgetSnapshotDTO: Decodable {
    struct Bucket: Decodable {
        let name: String
        let remaining: Double
        let isOverspent: Bool
    }
    let currencyCode: String
    let totalRemaining: Double
    let buckets: [Bucket]
}

// MARK: - Notification Names

extension Notification.Name {
    static let puldarFocusComposer = Notification.Name("puldarFocusComposer")
    static let puldarScanReceipt   = Notification.Name("puldarScanReceipt")
    static let puldarReplayOnboarding = Notification.Name("puldarReplayOnboarding")
}

// MARK: - Log Expense Intent

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an Expense"
    static let description = IntentDescription(
        "Open PULDAR and focus the expense input so you can start typing right away."
    )
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .puldarFocusComposer, object: nil)
        }
        return .result()
    }
}

// MARK: - Scan Receipt Intent

struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Receipt"
    static let description = IntentDescription(
        "Open PULDAR and launch the receipt scanner so you can photograph a receipt."
    )
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .puldarScanReceipt, object: nil)
        }
        return .result()
    }
}

// MARK: - Check Budget Intent

struct CheckBudgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Check My Budget"
    static let description = IntentDescription(
        "Hear how much budget you have remaining across each bucket this month."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await MainActor.run { budgetSummary }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }

    @MainActor
    private var budgetSummary: String {
        guard
            let data = UserDefaults(suiteName: "group.marcshaw.PULDAR")?
                .data(forKey: "widgetBudgetSnapshot"),
            let snapshot = try? JSONDecoder().decode(BudgetSnapshotDTO.self, from: data)
        else {
            return "Open PULDAR first so it can load your budget snapshot."
        }

        let code = snapshot.currencyCode
        let totalRemaining = snapshot.totalRemaining.formatted(.currency(code: code))

        var lines: [String] = [
            "You have \(totalRemaining) remaining this month."
        ]

        for bucket in snapshot.buckets {
            let amt = bucket.remaining.formatted(.currency(code: code))
            if bucket.isOverspent {
                let over = (-bucket.remaining).formatted(.currency(code: code))
                lines.append("\(bucket.name) is \(over) over budget.")
            } else {
                lines.append("\(bucket.name): \(amt) left.")
            }
        }

        return lines.joined(separator: " ")
    }
}

// MARK: - App Shortcuts

struct PULDARAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense in \(.applicationName)",
                "Track spending in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "Scan a receipt in \(.applicationName)",
                "Scan receipt with \(.applicationName)"
            ],
            shortTitle: "Scan Receipt",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: CheckBudgetIntent(),
            phrases: [
                "Check my budget in \(.applicationName)",
                "How much budget left in \(.applicationName)",
                "Budget remaining in \(.applicationName)"
            ],
            shortTitle: "Check Budget",
            systemImageName: "chart.pie.fill"
        )
    }
}
