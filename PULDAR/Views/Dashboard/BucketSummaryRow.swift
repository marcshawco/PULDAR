import SwiftUI

/// Compact progress bar for a single budget bucket.
///
/// The fill colour turns `overspend` red when the user exceeds
/// the bucket's allocation.  Text also shifts to red.
struct BucketSummaryRow: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.colorScheme) private var colorScheme
    let status: BudgetEngine.BucketStatus
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    @State private var animatedProgress: Double = 0

    init(
        status: BudgetEngine.BucketStatus,
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.status = status
        self.isSelected = isSelected
        self.onTap = onTap
        _animatedProgress = State(initialValue: Self.sanitizedProgress(status.progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // Bucket icon + name
                Image(systemName: status.bucket.icon)
                    .font(.system(size: 11, weight: .thin))
                    .foregroundStyle(barColor)

                Text(status.bucket.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(textColor)

                Spacer()

                // Spent / Budget
                Text(safeSpent.formattedCurrency(code: appPreferences.currencyCode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textColor)

                Text("/ \(safeBudgeted.formattedCurrency(code: appPreferences.currencyCode))")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }

            if overByAmount > 0 {
                HStack {
                    Text("Over by \(overByAmount.formattedCurrency(code: appPreferences.currencyCode))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.overspend)
                        )
                    Spacer()
                }
            } else {
                HStack {
                    Text("Left \(remainingAmount.formattedCurrency(code: appPreferences.currencyCode))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor)
                        .frame(width: safeWidth(geo.size.width) * safeAnimatedProgress)
                }
            }
            .frame(height: 5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? status.bucket.color.opacity(0.12) : Color.clear)
        )
        .onAppear {
            snapAnimatedProgress()
        }
        .onChange(of: status.spent) {
            updateAnimatedProgress(duration: 0.5, bounce: 0.12)
        }
        .onChange(of: status.budgeted) {
            updateAnimatedProgress(duration: 0.5, bounce: 0.12)
        }
        .onChange(of: status.progress) {
            updateAnimatedProgress(duration: 0.5, bounce: 0.12)
        }
        .onChange(of: colorScheme) {
            snapAnimatedProgress()
        }
    }

    // MARK: - Colours

    private var barColor: Color {
        status.isOverspent ? AppColors.overspend : status.bucket.color
    }

    private var textColor: Color {
        status.isOverspent ? AppColors.overspend : AppColors.textPrimary
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
        Self.sanitizedProgress(status.progress)
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

    private func snapAnimatedProgress() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            animatedProgress = safeProgress
        }
    }

    private static func sanitizedProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1.5)
    }
}
