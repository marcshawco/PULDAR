import SwiftUI

/// The big net-worth number at the top of the Folio screen.
///
/// Mirrors the Dashboard hero: 56pt ultra-light, monospaced, colour-coded —
/// red when net worth is negative (you owe more than you own).
struct FolioHeroView: View {
    @Environment(AppPreferences.self) private var appPreferences
    let netWorth: Double
    let assetsTotal: Double
    let fundsTotal: Double
    let liabilitiesTotal: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroFormattedAmount)
                .font(.system(size: 56, weight: .ultraLight))
                .kerning(-2)
                .foregroundStyle(netWorth < 0 ? AppColors.overspend : AppColors.textPrimary)
                .monospacedDigit()

            Text("net worth")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 8)

            HStack(spacing: 8) {
                breakdownLabel(FolioKind.asset.displayName, assetsTotal)
                separator
                breakdownLabel(FolioKind.fund.displayName, fundsTotal)
                separator
                breakdownLabel(FolioKind.liability.displayName, liabilitiesTotal)
            }
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var separator: some View {
        Circle()
            .fill(AppColors.border)
            .frame(width: 3, height: 3)
    }

    private func breakdownLabel(_ title: String, _ amount: Double) -> some View {
        Text("\(title) \(amount.formattedCurrency(code: appPreferences.currencyCode))")
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textTertiary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var heroFormattedAmount: String {
        let value = abs(netWorth)
        let formatted = value.formattedCurrency(code: appPreferences.currencyCode)
        return netWorth < 0 ? "-\(formatted)" : formatted
    }
}
