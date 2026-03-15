import SwiftUI
import WidgetKit

private struct WidgetBudgetSnapshot: Codable {
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
    let totalRemaining: Double
    let totalBudget: Double
    let totalSpent: Double
    let buckets: [Bucket]
}

private enum WidgetBudgetSnapshotReader {
    static let appGroupID = "group.marcshaw.PULDAR"
    static let fileName = "widget-budget-snapshot.json"

    static func load() -> WidgetBudgetSnapshot? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }

        let url = containerURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetBudgetSnapshot.self, from: data)
    }
}

private struct PULDARBudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetBudgetSnapshot?
}

private struct PULDARBudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PULDARBudgetEntry {
        PULDARBudgetEntry(
            date: .now,
            snapshot: WidgetBudgetSnapshot(
                generatedAt: .now,
                totalRemaining: 3180,
                totalBudget: 5000,
                totalSpent: 1820,
                buckets: [
                    .init(id: "fundamentals", name: "Fundamentals", subtitle: "Needs", remaining: 624, budgeted: 3000, spent: 2376, isOverspent: false),
                    .init(id: "fun", name: "Fun", subtitle: "Wants", remaining: 706, budgeted: 1000, spent: 294, isOverspent: false),
                    .init(id: "future", name: "Future", subtitle: "Savings & Debt", remaining: 350, budgeted: 1000, spent: 650, isOverspent: false),
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PULDARBudgetEntry) -> Void) {
        completion(PULDARBudgetEntry(date: .now, snapshot: WidgetBudgetSnapshotReader.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PULDARBudgetEntry>) -> Void) {
        let entry = PULDARBudgetEntry(date: .now, snapshot: WidgetBudgetSnapshotReader.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct PULDARBudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PULDARBudgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall:
                    smallWidget(snapshot: snapshot)
                default:
                    mediumWidget(snapshot: snapshot)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func smallWidget(snapshot: WidgetBudgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PULDAR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(snapshot.totalRemaining, format: .currency(code: "USD"))
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.75)

            Text("Remaining this month")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(snapshot.buckets.prefix(3)) { bucket in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: bucket.id))
                            .frame(width: 7, height: 7)
                        Text(bucket.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(bucket.remaining, format: .currency(code: "USD"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(bucket.isOverspent ? .red : .primary)
                    }
                }
            }
        }
        .padding(14)
    }

    private func mediumWidget(snapshot: WidgetBudgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Budget Remaining")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.totalRemaining, format: .currency(code: "USD"))
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Text("Daily glance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(snapshot.buckets.prefix(3)) { bucket in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color(for: bucket.id))
                            .frame(width: 6)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(bucket.name)
                                .font(.subheadline.weight(.semibold))
                            Text(bucket.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(bucket.remaining, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(bucket.isOverspent ? .red : .primary)
                            Text("\(bucket.spent, format: .currency(code: "USD")) spent")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PULDAR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Open the app to load your three-budget snapshot.")
                .font(.caption)
        }
        .padding(16)
    }

    private func color(for bucketID: String) -> Color {
        switch bucketID {
        case "fundamentals": return Color(red: 0.35, green: 0.55, blue: 0.78)
        case "fun": return Color(red: 0.55, green: 0.75, blue: 0.52)
        default: return Color(red: 0.68, green: 0.52, blue: 0.82)
        }
    }
}

struct PULDARBudgetWidget: Widget {
    let kind: String = "PULDARBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PULDARBudgetProvider()) { entry in
            PULDARBudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget Balances")
        .description("See your remaining Fundamentals, Fun, and Future balances at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PULDARWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PULDARBudgetWidget()
    }
}
