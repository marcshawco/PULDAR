import SwiftUI

/// A single Folio item row (name + category + current value).
///
/// Reuses the expanded-row styling from `BucketSummaryRow`. Liability values
/// are tinted to signal money owed.
struct FolioItemRow: View {
    @Environment(AppPreferences.self) private var appPreferences
    let item: FolioItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(item.folioCategory.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Text(valuePrefix + item.currentValue.formattedCurrency(code: appPreferences.currencyCode))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.itemKind == .liability ? AppColors.overspend : AppColors.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.leading, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var valuePrefix: String {
        item.itemKind == .liability ? "−" : ""
    }
}
