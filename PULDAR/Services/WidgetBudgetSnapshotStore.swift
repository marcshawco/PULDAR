import Foundation
import WidgetKit

struct WidgetBudgetSnapshot: Codable {
    struct Bucket: Codable, Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let remaining: Double
        let budgeted: Double
        let spent: Double
        let isOverspent: Bool
    }

    let generatedAt: Date
    let currencyCode: String
    let totalRemaining: Double
    let totalBudget: Double
    let totalSpent: Double
    let buckets: [Bucket]
}

enum WidgetBudgetSnapshotStore {
    static let appGroupID = "group.marcshaw.PULDAR"
    private static let fileName = "widget-budget-snapshot.json"

    static func publish(
        statuses: [BudgetEngine.BucketStatus],
        totalBudget: Double,
        totalSpent: Double,
        currencyCode: String
    ) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return
        }

        let snapshot = WidgetBudgetSnapshot(
            generatedAt: .now,
            currencyCode: currencyCode,
            totalRemaining: totalBudget - totalSpent,
            totalBudget: totalBudget,
            totalSpent: totalSpent,
            buckets: statuses.map { status in
                WidgetBudgetSnapshot.Bucket(
                    id: status.bucket.id,
                    name: status.bucket.rawValue,
                    subtitle: status.bucket.subtitle,
                    remaining: status.remaining,
                    budgeted: status.budgeted,
                    spent: status.spent,
                    isOverspent: status.isOverspent
                )
            }
        )

        let destinationURL = containerURL.appendingPathComponent(fileName)

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: destinationURL, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            #if DEBUG
            print("Widget snapshot publish failed: \(error)")
            #endif
        }
    }
}
