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
    @State private var appeared = false

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

    var body: some View {
        Chart(chartData) { status in
            SectorMark(
                angle: .value("Spent", angleValue(for: status)),
                innerRadius: .ratio(0.618),   // Golden-ratio cutout
                angularInset: 2.0
            )
            .foregroundStyle(sectorColor(for: status))
            .cornerRadius(5)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 2) {
                if totalSpent > 0 {
                    Text("Spent")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(totalSpent, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .contentTransition(.numericText())
                } else {
                    Text("No expenses")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .frame(height: 220)
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(duration: 1.0, bounce: 0.25)) {
                appeared = true
            }
        }
    }

    // MARK: - Colour Logic

    private func sectorColor(for status: BudgetEngine.BucketStatus) -> Color {
        if totalSpent == 0 {
            return status.bucket.color.opacity(0.25)
        }
        return status.isOverspent ? AppColors.overspend : status.bucket.color
    }

    private func sanitizedAmount(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private func angleValue(for status: BudgetEngine.BucketStatus) -> Double {
        let spent = sanitizedAmount(status.spent)
        return appeared ? max(spent, 0.01) : 0.01
    }
}
