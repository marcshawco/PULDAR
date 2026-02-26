import SwiftUI

/// Compact progress bar for a single budget bucket.
///
/// The fill colour turns `overspend` red when the user exceeds
/// the bucket's allocation.  Text also shifts to red.
struct BucketSummaryRow: View {
    let status: BudgetEngine.BucketStatus
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
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.2)) {
                animatedProgress = safeProgress
            }
        }
        .onChange(of: status.spent) {
            withAnimation(.spring(duration: 0.5)) {
                animatedProgress = safeProgress
            }
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
}
