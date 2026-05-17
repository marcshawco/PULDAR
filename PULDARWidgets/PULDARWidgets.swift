import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Brand

private enum WidgetBrand {
    static let fundamentals = Color(red: 0.227, green: 0.361, blue: 0.678) // #3A5CAD
    static let fun          = Color(red: 0.165, green: 0.502, blue: 0.337) // #2A8056
    static let future       = Color(red: 0.788, green: 0.412, blue: 0.141) // #C96924

    static func color(for bucketID: String) -> Color {
        switch bucketID.lowercased() {
        case "fundamentals": return fundamentals
        case "fun":          return fun
        case "future":       return future
        default:             return .primary
        }
    }
}

// MARK: - Snapshot model & reader

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

// MARK: - Budget widget configuration

private enum BudgetWidgetMode: String, AppEnum {
    case remaining
    case spending

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Budget Widget Mode")
    static let caseDisplayRepresentations: [BudgetWidgetMode: DisplayRepresentation] = [
        .remaining: DisplayRepresentation(title: "Remaining"),
        .spending:  DisplayRepresentation(title: "Spending")
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

// MARK: - Budget timeline

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
                    .init(id: "fundamentals", name: "Fundamentals", subtitle: "Needs",          remaining: 624, budgeted: 3000, spent: 2376, isOverspent: false),
                    .init(id: "fun",          name: "Fun",          subtitle: "Wants",          remaining: 706, budgeted: 1000, spent: 294,  isOverspent: false),
                    .init(id: "future",       name: "Future",       subtitle: "Savings & Debt", remaining: 350, budgeted: 1000, spent: 650,  isOverspent: false),
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

// MARK: - Budget widget view

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
                case .systemSmall: smallBudget(snapshot)
                default:           mediumBudget(snapshot)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Small

    private func smallBudget(_ snapshot: WidgetBudgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            KickerLabel(text: "PULDAR")

            Spacer(minLength: 6)

            Text(primaryTotal(for: snapshot), format: .currency(code: snapshot.currencyCode))
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(selectedMode == .remaining ? "left this month" : "spent this month")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 10)

            stackedBucketBars(snapshot.buckets)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                ForEach(snapshot.buckets.prefix(3)) { bucket in
                    bucketChip(bucket)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "puldar://quick-add"))
    }

    private func stackedBucketBars(_ buckets: [WidgetBudgetSnapshot.Bucket]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(buckets.prefix(3)) { bucket in
                    let share = totalShare(for: bucket, in: buckets)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(WidgetBrand.color(for: bucket.id).opacity(bucket.isOverspent ? 0.5 : 1))
                        .frame(width: max(4, geo.size.width * share))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 4)
    }

    private func bucketChip(_ bucket: WidgetBudgetSnapshot.Bucket) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(WidgetBrand.color(for: bucket.id))
                .frame(width: 5, height: 5)
            Text(bucket.name.prefix(4))
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Medium

    private func mediumBudget(_ snapshot: WidgetBudgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                KickerLabel(text: "PULDAR")
                Spacer()
                KickerLabel(text: selectedMode == .remaining ? "REMAINING" : "SPENDING")
            }

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(primaryTotal(for: snapshot), format: .currency(code: snapshot.currencyCode))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(selectedMode == .remaining ? "of \(snapshot.totalBudget.formatted(.currency(code: snapshot.currencyCode)))"
                                                : "of \(snapshot.totalBudget.formatted(.currency(code: snapshot.currencyCode)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 14)

            VStack(spacing: 9) {
                ForEach(snapshot.buckets.prefix(3)) { bucket in
                    bucketMediumRow(bucket, currencyCode: snapshot.currencyCode)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "puldar://quick-add"))
    }

    private func bucketMediumRow(_ bucket: WidgetBudgetSnapshot.Bucket, currencyCode: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(WidgetBrand.color(for: bucket.id))
                    .frame(width: 6, height: 6)

                Text(bucket.name)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(displayAmount(for: bucket, currencyCode: currencyCode))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(bucket.isOverspent && selectedMode == .remaining ? .red : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(WidgetBrand.color(for: bucket.id).opacity(bucket.isOverspent ? 0.45 : 1))
                        .frame(width: max(2, geo.size.width * progress(for: bucket)))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            KickerLabel(text: "PULDAR")
            Text("Open the app to load your budget snapshot.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .widgetURL(URL(string: "puldar://quick-add"))
    }

    // MARK: Helpers

    private func primaryTotal(for snapshot: WidgetBudgetSnapshot) -> Double {
        selectedMode == .remaining ? snapshot.totalRemaining : snapshot.totalSpent
    }

    private func displayAmount(for bucket: WidgetBudgetSnapshot.Bucket, currencyCode: String) -> String {
        let value = selectedMode == .remaining ? bucket.remaining : bucket.spent
        return value.formatted(.currency(code: currencyCode))
    }

    private func progress(for bucket: WidgetBudgetSnapshot.Bucket) -> Double {
        guard bucket.budgeted > 0 else { return 0 }
        let raw = selectedMode == .remaining
            ? max(0, bucket.remaining) / bucket.budgeted
            : bucket.spent / bucket.budgeted
        return min(1, max(0, raw))
    }

    private func totalShare(for bucket: WidgetBudgetSnapshot.Bucket, in buckets: [WidgetBudgetSnapshot.Bucket]) -> Double {
        let denominator = selectedMode == .remaining
            ? buckets.reduce(0) { $0 + max(0, $1.remaining) }
            : buckets.reduce(0) { $0 + max(0, $1.spent) }
        guard denominator > 0 else { return 1.0 / Double(max(buckets.count, 1)) }
        let value = selectedMode == .remaining
            ? max(0, bucket.remaining)
            : max(0, bucket.spent)
        return value / denominator
    }
}

private struct KickerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .kerning(1.4)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Budget widget

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

// MARK: - Quick Add

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
            case .systemSmall: smallQuickAdd
            default:           mediumQuickAdd
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var smallQuickAdd: some View {
        Link(destination: deepLink("puldar://quick-add")) {
            VStack(alignment: .leading, spacing: 0) {
                KickerLabel(text: "PULDAR")

                Spacer(minLength: 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 10)

                Text("Add expense")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let snapshot = entry.snapshot {
                    Text("\(snapshot.totalRemaining.formatted(.currency(code: snapshot.currencyCode))) left")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }

    private var mediumQuickAdd: some View {
        VStack(alignment: .leading, spacing: 0) {
            KickerLabel(text: "PULDAR · QUICK ADD")

            Spacer(minLength: 8)

            if let snapshot = entry.snapshot {
                Text(snapshot.totalRemaining, format: .currency(code: snapshot.currencyCode))
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("left this month")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("Log an expense in one tap.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                quickActionTile(url: "puldar://quick-add",   title: "Type", icon: "text.cursor")
                quickActionTile(url: "puldar://scan-receipt", title: "Scan", icon: "camera.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private func quickActionTile(url: String, title: String, icon: String) -> some View {
        Link(destination: deepLink(url)) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
        }
    }

    private func deepLink(_ urlString: String) -> URL {
        URL(string: urlString) ?? URL(fileURLWithPath: "/")
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

// MARK: - Bundle

@main
struct PULDARWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PULDARBudgetWidget()
        PULDARQuickAddWidget()
    }
}
