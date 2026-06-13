import SwiftUI

/// A collapsible balance-sheet group (Assets / Funds / Liabilities).
///
/// The header mirrors `BucketSummaryRow`: a colour dot, the group name in
/// uppercase, the item count, the group subtotal, and a rotating chevron.
struct FolioGroupSection: View {
    @Environment(AppPreferences.self) private var appPreferences
    let kind: FolioKind
    let total: Double
    let items: [FolioItem]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelectItem: (FolioItem) -> Void
    let onAddItem: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .center) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(kind.color)
                            .frame(width: 7, height: 7)

                        Text(kind.displayName)
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.textSecondary)

                        Text("· \(items.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                            .monospacedDigit()
                    }

                    Spacer()

                    Text(valuePrefix + total.formattedCurrency(code: appPreferences.currencyCode))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(kind == .liability ? AppColors.overspend : AppColors.textSecondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.22), value: isExpanded)
                        .padding(.leading, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                if items.isEmpty {
                    Text("No \(kind.displayName.lowercased()) yet")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 34)
                        }
                        FolioItemRow(item: item) { onSelectItem(item) }
                    }
                }

                Divider().padding(.leading, 34)
                addRow
            }
        }
        .background(isExpanded ? kind.color.opacity(0.05) : AppColors.secondaryBg)
    }

    private var addRow: some View {
        Button(action: onAddItem) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(kind.color)

                Text("Add \(kind.singularName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(kind.color)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.leading, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var valuePrefix: String {
        kind == .liability && total > 0 ? "−" : ""
    }
}
