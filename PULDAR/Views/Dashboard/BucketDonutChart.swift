import SwiftUI
import Charts

/// Animated donut chart showing the 3-bucket spend breakdown.
///
/// - Inner label shows the total monthly spend.
/// - Sector colours shift to red when a bucket is overspent.
/// - The chart gently expands on first appearance via a spring animation.
struct BucketDonutChart: View {
    let statuses: [BudgetEngine.BucketStatus]
    @State private var appeared = false

    /// Ensure the chart always has something to show even with $0 spent.
    private var chartData: [BudgetEngine.BucketStatus] {
        let hasSpending = statuses.contains { $0.spent > 0 }
        return hasSpending ? statuses : placeholderData
    }

    private var placeholderData: [BudgetEngine.BucketStatus] {
        BudgetBucket.allCases.map {
            .init(bucket: $0, budgeted: $0.targetPercentage * 100, spent: $0.targetPercentage * 100)
        }
    }

    private var totalSpent: Double {
        statuses.reduce(0) { $0 + $1.spent }
    }

    var body: some View {
        Chart(chartData) { status in
            SectorMark(
                angle: .value("Spent", appeared ? max(status.spent, 0.01) : 0.01),
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
}
