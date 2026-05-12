import SwiftUI

/// Empty state shown when no expenses are logged.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No expenses yet")
                .font(.headline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)

            Text("Try something like")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)

            Text("\"coffee at starbucks 5.50\"")
                .font(.subheadline)
                .italic()
                .foregroundStyle(AppColors.accent.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }
}

#Preview {
    EmptyStateView()
}
