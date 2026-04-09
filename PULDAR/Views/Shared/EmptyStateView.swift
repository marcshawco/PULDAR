import SwiftUI

/// Friendly illustration empty state shown when no expenses are logged.
///
/// Uses a layered SF Symbol composition rather than a boring blank message.
struct EmptyStateView: View {
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760 || proxy.size.width < 390

            VStack(spacing: compact ? 16 : 20) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppColors.accent.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: compact ? 64 : 80
                            )
                        )
                        .frame(width: compact ? 132 : 160, height: compact ? 132 : 160)

                    Image(systemName: "creditcard")
                        .font(.system(size: compact ? 40 : 48, weight: .ultraLight))
                        .foregroundStyle(AppColors.textTertiary)
                        .offset(y: floatOffset)

                    Image(systemName: "sparkle")
                        .font(.system(size: compact ? 12 : 14, weight: .thin))
                        .foregroundStyle(AppColors.accent.opacity(0.6))
                        .offset(x: compact ? 26 : 32, y: (compact ? -20 : -24) + floatOffset * 0.5)

                    Image(systemName: "plus.circle")
                        .font(.system(size: compact ? 14 : 16, weight: .thin))
                        .foregroundStyle(AppColors.textSecondary)
                        .offset(x: compact ? -24 : -28, y: (compact ? 16 : 18) + floatOffset * 0.3)
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
            .offset(y: proxy.size.height * 0.08)
            .padding(.vertical, compact ? 32 : 48)
        }
    }
}

#Preview {
    EmptyStateView()
}
