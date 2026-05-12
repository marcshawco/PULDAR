import SwiftUI

struct BucketSummaryRow: View {
    @Environment(AppPreferences.self) private var appPreferences
    let status: BudgetEngine.BucketStatus
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    var items: [Expense] = []
    var recurringItems: [RecurringExpense] = []
    var onEditExpense: ((Expense) -> Void)? = nil
    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onTap?() }) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(barColor)
                                .frame(width: 7, height: 7)

                            Text(status.bucket.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .kerning(1.1)
                                .textCase(.uppercase)
                                .foregroundStyle(textColor)

                            Text("· \(entryCount)")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                                .monospacedDigit()
                        }

                        Spacer()

                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(safeSpent.formattedCurrency(code: appPreferences.currencyCode))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(textColor)
                                .monospacedDigit()

                            Text("/ \(safeBudgeted.formattedCurrency(code: appPreferences.currencyCode))")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                                .monospacedDigit()
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                            .rotationEffect(.degrees(isSelected ? 180 : 0))
                            .animation(.easeInOut(duration: 0.22), value: isSelected)
                            .padding(.leading, 2)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(AppColors.border)

                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(barColor)
                                .frame(width: safeWidth(geo.size.width) * safeAnimatedProgress)
                        }
                    }
                    .frame(height: 3)

                    HStack {
                        Text(overByAmount > 0
                             ? "Over by \(overByAmount.formattedCurrency(code: appPreferences.currencyCode))"
                             : "\(remainingAmount.formattedCurrency(code: appPreferences.currencyCode)) remaining")
                            .font(.system(size: 11))
                            .foregroundStyle(overByAmount > 0 ? AppColors.overspend : AppColors.textTertiary)

                        Spacer()

                        Text("\(min(Int(round(safeProgress * 100)), 999))%")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline expanded transactions
            if isSelected {
                Divider()

                if entryCount == 0 {
                    Text("No entries yet")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, expense in
                            if index > 0 {
                                Divider().padding(.leading, 34)
                            }
                            Button {
                                onEditExpense?(expense)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(expense.normalizedMerchant)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .lineLimit(1)

                                        Text("\(expense.category.capitalized) · \(expense.date.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }

                                    Spacer()

                                    Text(expense.amount.formattedCurrency(code: appPreferences.currencyCode))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 20)
                                .padding(.leading, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(Array(recurringItems.enumerated()), id: \.element.persistentModelID) { index, recurring in
                            if !items.isEmpty || index > 0 {
                                Divider().padding(.leading, 34)
                            }
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(recurring.budgetBucket.color)
                                    .frame(width: 5, height: 5)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(recurring.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)

                                    Text("Recurring monthly · \(recurring.budgetBucket.rawValue)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppColors.textTertiary)
                                }

                                Spacer()

                                Text(recurring.safeAmount.formattedCurrency(code: appPreferences.currencyCode))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 20)
                            .padding(.leading, 14)
                            .padding(.vertical, 10)
                        }

                        // Subtotal
                        Divider()
                        HStack {
                            Text("Subtotal")
                                .font(.system(size: 10, weight: .bold))
                                .kerning(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(AppColors.textTertiary)

                            Spacer()

                            Text(entrySubtotal.formattedCurrency(code: appPreferences.currencyCode))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 20)
                        .padding(.leading, 14)
                        .padding(.vertical, 9)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(isSelected ? barColor.opacity(0.05) : AppColors.secondaryBg)
        .onAppear {
            updateAnimatedProgress(duration: 0.7, bounce: 0.2)
        }
        .onChange(of: status.spent) {
            updateAnimatedProgress(duration: 0.5, bounce: 0.12)
        }
        .onChange(of: status.budgeted) {
            updateAnimatedProgress(duration: 0.5, bounce: 0.12)
        }
    }

    private var barColor: Color {
        status.isOverspent ? AppColors.overspend : status.bucket.color
    }

    private var textColor: Color {
        status.isOverspent ? AppColors.overspend : AppColors.textSecondary
    }

    private var entryCount: Int {
        items.count + recurringItems.count
    }

    private var entrySubtotal: Double {
        items.reduce(0) { $0 + $1.amount } + recurringItems.reduce(0) { $0 + $1.safeAmount }
    }

    private var safeSpent: Double {
        status.spent.isFinite ? status.spent : 0
    }

    private var safeBudgeted: Double {
        status.budgeted.isFinite ? max(status.budgeted, 0) : 0
    }

    private var overByAmount: Double {
        guard safeSpent > safeBudgeted else { return 0 }
        return safeSpent - safeBudgeted
    }

    private var remainingAmount: Double {
        max(safeBudgeted - safeSpent, 0)
    }

    private var safeProgress: Double {
        let value = status.progress
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1.5)
    }

    private var safeAnimatedProgress: Double {
        guard animatedProgress.isFinite else { return 0 }
        return min(max(animatedProgress, 0), 1.0)
    }

    private func safeWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func updateAnimatedProgress(duration: Double, bounce: Double) {
        withAnimation(.spring(duration: duration, bounce: bounce)) {
            animatedProgress = safeProgress
        }
    }
}
