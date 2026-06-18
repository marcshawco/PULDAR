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

    /// Inner radius of the donut as a fraction of the outer radius. Used both
    /// for the `SectorMark` and to size the centre label so it always fits
    /// inside the hole.
    private let innerRadiusRatio: CGFloat = 0.618

    var body: some View {
        VStack(spacing: 16) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Total", sectorWeight(for: slice)),
                    innerRadius: .ratio(innerRadiusRatio),
                    angularInset: 2.0
                )
                .foregroundStyle(slice.kind.color)
                .cornerRadius(5)
            }
            .chartLegend(.hidden)
            .chartBackground { _ in
                GeometryReader { geo in
                    let holeDiameter = min(geo.size.width, geo.size.height) * innerRadiusRatio
                    centerView(holeDiameter: holeDiameter)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                }
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

    /// Net-worth label inscribed inside the donut hole. The frame is derived
    /// from the actual hole diameter so the value scales to fit and never
    /// spills under the surrounding ring.
    private func centerView(holeDiameter: CGFloat) -> some View {
        // Inscribe the content in the hole with a small inset so glyphs never
        // touch the ring. Width is the limiting dimension for the number.
        let contentWidth = holeDiameter * 0.86
        let contentHeight = holeDiameter * 0.78

        return VStack(spacing: 2) {
            Text("Net Worth")
                .font(.system(size: max(9, holeDiameter * 0.11), weight: .regular))
                .foregroundStyle(AppColors.textTertiary)

            Text(netWorthText)
                .font(.system(size: holeDiameter * 0.30, weight: .bold, design: .rounded))
                .foregroundStyle(netWorth < 0 ? AppColors.overspend : AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .allowsTightening(true)
        }
        .multilineTextAlignment(.center)
        .frame(width: contentWidth, height: contentHeight, alignment: .center)
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
