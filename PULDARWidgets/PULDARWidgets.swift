import AppIntents
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
    let currencyCode: String
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

private enum BudgetWidgetMode: String, AppEnum {
    case remaining
    case spending

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Budget Widget Mode")
    static let caseDisplayRepresentations: [BudgetWidgetMode: DisplayRepresentation] = [
        .remaining: DisplayRepresentation(title: "Remaining"),
        .spending: DisplayRepresentation(title: "Spending")
    ]
}

private struct BudgetWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Budget View"
    static let description = IntentDescription(
        "Choose whether the widget emphasizes remaining funds or current spending."
    )

    @Parameter(title: "Display")
    var mode: BudgetWidgetMode?

    init() {
        mode = .remaining
    }
}

private struct PULDARBudgetEntry: TimelineEntry {
    let date: Date
    let configuration: BudgetWidgetConfigurationIntent
    let snapshot: WidgetBudgetSnapshot?
}

private struct PULDARBudgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PULDARBudgetEntry {
        PULDARBudgetEntry(
            date: .now,
            configuration: BudgetWidgetConfigurationIntent(),
            snapshot: WidgetBudgetSnapshot(
                generatedAt: .now,
                currencyCode: "USD",
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

    func snapshot(for configuration: BudgetWidgetConfigurationIntent, in context: Context) async -> PULDARBudgetEntry {
        PULDARBudgetEntry(date: .now, configuration: configuration, snapshot: WidgetBudgetSnapshotReader.load())
    }

    func timeline(for configuration: BudgetWidgetConfigurationIntent, in context: Context) async -> Timeline<PULDARBudgetEntry> {
        let entry = PULDARBudgetEntry(
            date: .now,
            configuration: configuration,
            snapshot: WidgetBudgetSnapshotReader.load()
        )
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

private struct PULDARBudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PULDARBudgetEntry

    private var selectedMode: BudgetWidgetMode {
        entry.configuration.mode ?? .remaining
    }

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

            Text(primaryTotal(for: snapshot), format: .currency(code: snapshot.currencyCode))
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.75)

            Text(selectedMode == .remaining ? "Remaining this month" : "Spent this month")
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
                        Text(displayAmount(for: bucket, currencyCode: snapshot.currencyCode))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(bucket.isOverspent && selectedMode == .remaining ? .red : .primary)
                    }
                }
            }
        }
        .padding(14)
        .widgetURL(URL(string: "puldar://quick-add"))
    }

    private func mediumWidget(snapshot: WidgetBudgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedMode == .remaining ? "Budget Remaining" : "Budget Spending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(primaryTotal(for: snapshot), format: .currency(code: snapshot.currencyCode))
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Text(selectedMode == .remaining ? "Allocation view" : "Spending view")
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
                            Text(displayAmount(for: bucket, currencyCode: snapshot.currencyCode))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(bucket.isOverspent && selectedMode == .remaining ? .red : .primary)
                            Text(secondaryLabel(for: bucket, currencyCode: snapshot.currencyCode))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .widgetURL(URL(string: "puldar://quick-add"))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PULDAR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Open the app to load your budget snapshot.")
                .font(.caption)
        }
        .padding(16)
        .widgetURL(URL(string: "puldar://quick-add"))
    }

    private func primaryTotal(for snapshot: WidgetBudgetSnapshot) -> Double {
        selectedMode == .remaining ? snapshot.totalRemaining : snapshot.totalSpent
    }

    private func displayAmount(for bucket: WidgetBudgetSnapshot.Bucket, currencyCode: String) -> String {
        let value = selectedMode == .remaining ? bucket.remaining : bucket.spent
        return value.formatted(.currency(code: currencyCode))
    }

    private func secondaryLabel(for bucket: WidgetBudgetSnapshot.Bucket, currencyCode: String) -> String {
        if selectedMode == .remaining {
            return "\(bucket.spent.formatted(.currency(code: currencyCode))) spent"
        }
        return "\(bucket.remaining.formatted(.currency(code: currencyCode))) left"
    }

    private func color(for bucketID: String) -> Color {
        switch bucketID {
        case "fundamentals":
            return Color(red: 0.35, green: 0.55, blue: 0.78)
        case "fun":
            return Color(red: 0.55, green: 0.75, blue: 0.52)
        default:
            return Color(red: 0.68, green: 0.52, blue: 0.82)
        }
    }
}

private struct PULDARBudgetWidget: Widget {
    let kind = "PULDARBudgetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BudgetWidgetConfigurationIntent.self,
            provider: PULDARBudgetProvider()
        ) { entry in
            PULDARBudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget Snapshot")
        .description("See either your remaining allocation or current spending across the three budgets.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct QuickAddEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetBudgetSnapshot?
}

private struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: .now, snapshot: WidgetBudgetSnapshotReader.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: .now, snapshot: WidgetBudgetSnapshotReader.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        let entry = QuickAddEntry(date: .now, snapshot: WidgetBudgetSnapshotReader.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct PULDARQuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickAddEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallQuickAdd
            default:
                mediumQuickAdd
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var smallQuickAdd: some View {
        Link(destination: URL(string: "puldar://quick-add")!) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("Quick Add")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Open PULDAR and start typing an expense right away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                if let snapshot = entry.snapshot {
                    Text("\(snapshot.totalRemaining.formatted(.currency(code: snapshot.currencyCode))) left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private var mediumQuickAdd: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.headline.weight(.semibold))

            Text("Jump straight into typing or scan a receipt in the app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Link(destination: URL(string: "puldar://quick-add")!) {
                    quickActionCard(
                        title: "Type Expense",
                        subtitle: "Focus the composer",
                        systemImage: "text.cursor"
                    )
                }

                Link(destination: URL(string: "puldar://scan-receipt")!) {
                    quickActionCard(
                        title: "Scan Receipt",
                        subtitle: "Open the camera flow",
                        systemImage: "camera"
                    )
                }
            }

            if let snapshot = entry.snapshot {
                Text("\(snapshot.totalRemaining.formatted(.currency(code: snapshot.currencyCode))) left this month")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func quickActionCard(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
    }
}

private struct PULDARQuickAddWidget: Widget {
    let kind = "PULDARQuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddProvider()) { entry in
            PULDARQuickAddWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Add Expense")
        .description("Open straight into typing an expense or scanning a receipt.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PULDARWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PULDARBudgetWidget()
        PULDARQuickAddWidget()
    }
}
