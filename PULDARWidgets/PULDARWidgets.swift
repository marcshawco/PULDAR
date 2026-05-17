import SwiftUI
import WidgetKit

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

// MARK: - Shared kicker label

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

// MARK: - Quick Add widget

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
        PULDARQuickAddWidget()
    }
}
