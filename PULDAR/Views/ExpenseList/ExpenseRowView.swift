import SwiftUI

/// A single expense row with progressive disclosure.
///
/// Tap to expand and reveal category, bucket, and original note.
/// Matching search text is highlighted in yellow.
struct ExpenseRowView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(CategoryManager.self) private var categoryManager
    let expense: Expense
    let highlightText: String
    var onEdit: (() -> Void)? = nil

    @State private var isExpanded = false

    private var displayCategory: String {
        categoryManager.displayName(forStoredCategory: expense.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 11) {
                Circle()
                    .fill(expense.budgetBucket.color)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    if highlightText.isEmpty {
                        Text(expense.normalizedMerchant)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Text(expense.normalizedMerchant.highlighted(matching: highlightText))
                            .font(.system(size: 14, weight: .medium))
                    }

                    Text(displayCategory.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Text(expense.date.shortRelative)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)

                Text(expense.amount < 0 ? "+" : "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(expense.amount < 0 ? AppColors.success : AppColors.textPrimary) +
                Text(expense.amount.formattedCurrency(code: appPreferences.currencyCode))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(expense.amount < 0 ? AppColors.success : AppColors.textPrimary)

                if onEdit != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Label {
                            if highlightText.isEmpty {
                                Text(displayCategory)
                            } else {
                                Text(displayCategory.highlighted(matching: highlightText))
                            }
                        } icon: {
                            Image(systemName: "tag")
                                .font(.system(size: 10, weight: .thin))
                        }

                        if expense.isOverspent {
                            Label("Overspent", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColors.overspend)
                        }
                    }
                    .font(.caption)

                    Label(expense.budgetBucket.rawValue,
                          systemImage: expense.budgetBucket.icon)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)

                    if !expense.notes.isEmpty {
                        Text("\"" + expense.notes + "\"")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .italic()
                    }
                }
                .padding(.leading, 17)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(AppColors.secondaryBg)
        .contentShape(Rectangle())
        .onTapGesture {
            if onEdit != nil {
                HapticManager.light()
                onEdit?()
            } else {
                HapticManager.light()
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
    }
}
