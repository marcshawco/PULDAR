import SwiftUI
import Charts

/// Animated donut chart showing the 3-bucket spend breakdown.
///
/// - Inner label shows the total monthly spend.
/// - Sector colours shift to red when a bucket is overspent.
/// - The chart gently expands on first appearance via a spring animation.
struct BucketDonutChart: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    let statuses: [BudgetEngine.BucketStatus]
    var selectedBucket: BudgetBucket? = nil
    var onBucketSelected: ((BudgetBucket?) -> Void)? = nil
    @State private var appeared = false
    @State private var displayMode: DonutDisplayMode = .spent
    @State private var selectedAngle: Double?

    private var sanitizedStatuses: [BudgetEngine.BucketStatus] {
        statuses.map { status in
            .init(
                bucket: status.bucket,
                budgeted: sanitizedAmount(status.budgeted),
                spent: sanitizedAmount(status.spent)
            )
        }
    }

    /// Ensure the chart always has something to show even with $0 spent.
    private var chartData: [BudgetEngine.BucketStatus] {
        let hasSpending = sanitizedStatuses.contains { $0.spent > 0 }
        return hasSpending ? sanitizedStatuses : placeholderData
    }

    private var placeholderData: [BudgetEngine.BucketStatus] {
        BudgetBucket.allCases.map {
            let placeholder = sanitizedAmount(budgetEngine.percentage(for: $0) * 100)
            return .init(bucket: $0, budgeted: placeholder, spent: placeholder)
        }
    }

    private var totalSpent: Double {
        sanitizedStatuses.reduce(0) { $0 + $1.spent }
    }

    private var totalBudget: Double {
        sanitizedStatuses.reduce(0) { partial, status in
            partial + sanitizedAmount(status.budgeted)
        }
    }

    private var totalLeft: Double {
        max(totalBudget - totalSpent, 0)
    }

    private var percentUsed: Double {
        guard totalBudget > 0 else { return 0 }
        return min(max(totalSpent / totalBudget, 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Donut Mode", selection: $displayMode) {
                ForEach(DonutDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Chart(chartData) { status in
                SectorMark(
                    angle: .value("Spent", sectorWeight(for: status)),
                    innerRadius: .ratio(0.618),   // Golden-ratio cutout
                    angularInset: 2.0
                )
                .foregroundStyle(sectorColor(for: status))
                .cornerRadius(5)
            }
            .chartAngleSelection(value: $selectedAngle)
            .chartLegend(.hidden)
            .chartBackground { _ in
                Group {
                    if totalSpent > 0 {
                        Button {
                            cycleDisplayMode()
                        } label: {
                            centerValueView
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityLabel(accessibilityLabel)
                        .accessibilityHint("Double tap to switch donut mode")
                    } else {
                        Text("No expenses")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(duration: 1.0, bounce: 0.25)) {
                appeared = true
            }
        }
        .onChange(of: selectedAngle) {
            guard totalSpent > 0 else { return }
            guard let angle = selectedAngle else {
                onBucketSelected?(nil)
                return
            }
            guard let tappedBucket = bucketForSelectedAngle(angle) else { return }
            let nextSelection: BudgetBucket? = (selectedBucket == tappedBucket) ? nil : tappedBucket
            onBucketSelected?(nextSelection)
            HapticManager.light()
        }
    }

    // MARK: - Colour Logic

    private func sectorColor(for status: BudgetEngine.BucketStatus) -> Color {
        if let selectedBucket, selectedBucket != status.bucket {
            let base = status.isOverspent ? AppColors.overspend : status.bucket.color
            return base.opacity(0.32)
        }
        if totalSpent == 0 {
            return status.bucket.color.opacity(0.25)
        }
        return status.isOverspent ? AppColors.overspend : status.bucket.color
    }

    private func sanitizedAmount(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private func sectorWeight(for status: BudgetEngine.BucketStatus) -> Double {
        let spent = sanitizedAmount(status.spent)
        return appeared ? max(spent, 0.01) : 0.01
    }

    private func bucketForSelectedAngle(_ angle: Double) -> BudgetBucket? {
        let values = chartData.map { max(sectorWeight(for: $0), 0.01) }
        let total = values.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }

        let normalized = angle.truncatingRemainder(dividingBy: total)
        var runningTotal: Double = 0
        for (index, value) in values.enumerated() {
            runningTotal += value
            if normalized <= runningTotal {
                return chartData[index].bucket
            }
        }
        return chartData.last?.bucket
    }

    private var centerValueView: some View {
        VStack(spacing: 2) {
            Text(displayMode.centerTitle)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
            Text(displayMode.centerValue(totalSpent: totalSpent, totalLeft: totalLeft, percentUsed: percentUsed))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())
            if displayMode == .breakdown {
                Text("\(totalSpent.formatted(.currency(code: "USD"))) of \(totalBudget.formatted(.currency(code: "USD")))")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private var accessibilityLabel: String {
        switch displayMode {
        case .spent:
            return "Spent funds \(totalSpent.formatted(.currency(code: "USD")))"
        case .remaining:
            return "Remaining funds \(totalLeft.formatted(.currency(code: "USD")))"
        case .breakdown:
            return "Budget used \(percentUsed.formatted(.percent.precision(.fractionLength(0))))"
        }
    }

    private func cycleDisplayMode() {
        displayMode = displayMode.next
        HapticManager.light()
    }

    private enum DonutDisplayMode: String, CaseIterable, Identifiable {
        case spent
        case remaining
        case breakdown

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spent: return "Spent"
            case .remaining: return "Remaining"
            case .breakdown: return "Breakdown"
            }
        }

        var centerTitle: String {
            switch self {
            case .spent: return "Spent"
            case .remaining: return "Remaining"
            case .breakdown: return "Used"
            }
        }

        func centerValue(totalSpent: Double, totalLeft: Double, percentUsed: Double) -> String {
            switch self {
            case .spent:
                return totalSpent.formatted(.currency(code: "USD"))
            case .remaining:
                return totalLeft.formatted(.currency(code: "USD"))
            case .breakdown:
                return percentUsed.formatted(.percent.precision(.fractionLength(0)))
            }
        }

        var next: DonutDisplayMode {
            switch self {
            case .spent: return .remaining
            case .remaining: return .breakdown
            case .breakdown: return .spent
            }
        }
    }
}
