import SwiftUI
import Charts

/// Donut chart of the three balance-sheet groups (assets / funds /
/// liabilities), with net worth shown in the centre.
///
/// Structurally mirrors `BucketDonutChart`: golden-ratio cutout, spring
/// appearance, and weights clamped to a tiny positive minimum so `SectorMark`
/// never receives a non-positive value.
struct FolioBreakdownChart: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let slices: [FolioEngine.GroupSummary]
    let netWorth: Double
    @State private var appeared = false

    private var chartHeight: CGFloat {
        horizontalSizeClass == .regular ? 280 : 210
    }

    private var centerValueFontSize: CGFloat {
        horizontalSizeClass == .regular ? 34 : 28
    }

    var body: some View {
        VStack(spacing: 16) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Total", sectorWeight(for: slice)),
                    innerRadius: .ratio(0.618),
                    angularInset: 2.0
                )
                .foregroundStyle(slice.kind.color)
                .cornerRadius(5)
            }
            .chartLegend(.hidden)
            .chartBackground { _ in
                centerView
            }
            .frame(height: chartHeight)

            legend
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(duration: 1.0, bounce: 0.25)) {
                appeared = true
            }
        }
    }

    private func sectorWeight(for slice: FolioEngine.GroupSummary) -> Double {
        let value = max(slice.total.isFinite ? slice.total : 0, 0)
        return appeared ? max(value, 0.01) : 0.01
    }

    private var centerView: some View {
        VStack(spacing: 2) {
            Text("Net Worth")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)

            Text(netWorthText)
                .font(.system(size: centerValueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(netWorth < 0 ? AppColors.overspend : AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
        }
        .multilineTextAlignment(.center)
        .frame(width: 160, height: 92, alignment: .center)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle()
                        .fill(slice.kind.color)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(slice.kind.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.textTertiary)

                        Text(slice.total.formattedCurrency(code: appPreferences.currencyCode))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var netWorthText: String {
        let value = abs(netWorth)
        let formatted = value.formattedCurrency(code: appPreferences.currencyCode)
        return netWorth < 0 ? "-\(formatted)" : formatted
    }
}
