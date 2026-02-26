import SwiftUI

/// A single expense row with progressive disclosure.
///
/// Tap to expand and reveal category, bucket, and original note.
/// Matching search text is highlighted in yellow.
struct ExpenseRowView: View {
    @Environment(CategoryManager.self) private var categoryManager
    let expense: Expense
    let highlightText: String

    @State private var isExpanded = false

    private var displayCategory: String {
        categoryManager.displayName(forStoredCategory: expense.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Primary row ────────────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                // Bucket colour pip
                Circle()
                    .fill(expense.budgetBucket.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    // Merchant (highlighted if searching)
                    if highlightText.isEmpty {
                        Text(expense.normalizedMerchant)
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text(expense.normalizedMerchant.highlighted(matching: highlightText))
                            .font(.subheadline.weight(.medium))
                    }

                    Text(expense.date.shortRelative)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Text(expense.amount, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(expense.amount < 0 ? .green : AppColors.textPrimary)
            }

            // ── Expanded detail ────────────────────────────────────────
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
                .padding(.leading, 18)   // Align under merchant text
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.secondaryBg)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.light()
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
