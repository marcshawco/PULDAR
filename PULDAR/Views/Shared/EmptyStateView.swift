import SwiftUI

/// Empty state shown when no expenses are logged.
struct EmptyStateView: View {
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760 || proxy.size.width < 390

            VStack(spacing: compact ? 16 : 20) {
                VStack(spacing: 6) {
                    Text("No expenses yet")
                        .font(compact ? .subheadline.weight(.medium) : .headline.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)

                    Text("Try something like")
                        .font(compact ? .footnote : .subheadline)
                        .foregroundStyle(AppColors.textTertiary)

                    Text("\"coffee at starbucks 5.50\"")
                        .font(compact ? .footnote : .subheadline)
                        .italic()
                        .foregroundStyle(AppColors.accent.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            .padding(.vertical, compact ? 32 : 48)
        }
    }
}

#Preview {
    EmptyStateView()
}
