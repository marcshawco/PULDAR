import SwiftUI

/// Friendly illustration empty state shown when no expenses are logged.
///
/// Uses a layered SF Symbol composition rather than a boring blank message.
struct EmptyStateView: View {
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.accent.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Card icon
                Image(systemName: "creditcard")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(AppColors.textTertiary)
                    .offset(y: floatOffset)

                // Sparkle accent
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .thin))
                    .foregroundStyle(AppColors.accent.opacity(0.6))
                    .offset(x: 32, y: -24 + floatOffset * 0.5)

                // Plus badge
                Image(systemName: "plus.circle")
                    .font(.system(size: 16, weight: .thin))
                    .foregroundStyle(AppColors.textSecondary)
                    .offset(x: -28, y: 18 + floatOffset * 0.3)
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.4)
                    .repeatForever(autoreverses: true)
                ) {
                    floatOffset = -6
                }
            }

            VStack(spacing: 6) {
                Text("No expenses yet")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.textSecondary)

                Text("Try something like")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textTertiary)

                Text("\"coffee at starbucks 5.50\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(AppColors.accent.opacity(0.7))
            }
        }
        .padding(.vertical, 48)
    }
}

#Preview {
    EmptyStateView()
}
