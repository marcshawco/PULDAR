import SwiftUI
import UIKit
import WidgetKit

// MARK: - Palette

/// Brand-aligned adaptive colors for the widget. Each `Color` resolves
/// per-trait at render time, so the same view automatically picks up
/// the system appearance change without a SwiftUI rebuild.
private enum WidgetPalette {
    /// Outer widget canvas. Warm cream in light mode, warm dark in dark mode.
    static let background = adaptive(
        light: UIColor(red: 0.961, green: 0.957, blue: 0.941, alpha: 1.0),  // #F5F4F0
        dark:  UIColor(red: 0.102, green: 0.094, blue: 0.082, alpha: 1.0)   // #1A1816
    )

    /// Subtle tile / button fill that sits one step above the canvas.
    static let tile = adaptive(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0),  // #FFFFFF
        dark:  UIColor(red: 0.165, green: 0.153, blue: 0.141, alpha: 1.0)   // #2A2724
    )

    /// Primary text — high contrast in both modes.
    static let ink = adaptive(
        light: UIColor(red: 0.059, green: 0.055, blue: 0.043, alpha: 1.0),  // #0F0E0B
        dark:  UIColor(red: 0.961, green: 0.957, blue: 0.941, alpha: 1.0)   // #F5F4F0
    )

    /// Muted secondary text.
    static let inkMuted = adaptive(
        light: UIColor(red: 0.541, green: 0.529, blue: 0.502, alpha: 1.0),  // #8A8780
        dark:  UIColor(red: 0.741, green: 0.725, blue: 0.686, alpha: 1.0)   // #BDB9AF
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
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

// MARK: - Shared kicker label

private struct KickerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .kerning(1.4)
            .textCase(.uppercase)
            .foregroundStyle(WidgetPalette.inkMuted)
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
        .containerBackground(for: .widget) {
            WidgetPalette.background
        }
    }

    private var smallQuickAdd: some View {
        Link(destination: deepLink("puldar://quick-add")) {
            VStack(alignment: .leading, spacing: 0) {
                KickerLabel(text: "PULDAR")

                Spacer(minLength: 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WidgetPalette.tile)
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(WidgetPalette.ink)
                }
                .widgetAccentable()

                Spacer(minLength: 10)

                Text("Add expense")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)

                if let snapshot = entry.snapshot {
                    Text("\(snapshot.totalRemaining.formatted(.currency(code: snapshot.currencyCode))) left")
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetPalette.inkMuted)
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
                    .foregroundStyle(WidgetPalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("left this month")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetPalette.inkMuted)
            } else {
                Text("Log an expense in one tap.")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.inkMuted)
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
                    .foregroundStyle(WidgetPalette.ink)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WidgetPalette.tile)
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
