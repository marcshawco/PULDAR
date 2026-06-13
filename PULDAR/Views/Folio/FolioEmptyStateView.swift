import SwiftUI

/// Empty state shown when no Folio items exist yet.
struct FolioEmptyStateView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Build your net worth")
                .font(.headline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)

            Text("Add a fund, asset, or debt — or just say")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)

            Text("\"my savings is 5,000\"")
                .font(.subheadline)
                .italic()
                .foregroundStyle(AppColors.accent.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    FolioEmptyStateView()
}
