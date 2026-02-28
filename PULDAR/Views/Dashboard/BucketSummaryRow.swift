import SwiftUI

/// Compact progress bar for a single budget bucket.
///
/// The fill colour turns `overspend` red when the user exceeds
/// the bucket's allocation.  Text also shifts to red.
struct BucketSummaryRow: View {
    let status: BudgetEngine.BucketStatus
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    @State private var animatedProgress: Double = 0

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
                Text(safeSpent, format: .currency(code: "USD"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textColor)

                Text("/ \(safeBudgeted, format: .currency(code: "USD"))")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }

            if overByAmount > 0 {
                HStack {
                    Text("Over by \(overByAmount, format: .currency(code: "USD"))")
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
                    Text("Left \(remainingAmount, format: .currency(code: "USD"))")
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
            updateAnimatedProgress(duration: 0.7, bounce: 0.2)
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
