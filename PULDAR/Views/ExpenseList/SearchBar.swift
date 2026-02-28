import SwiftUI

/// Notion-style minimal search bar.
struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .thin))
                .foregroundStyle(AppColors.textTertiary)

            TextField("Search expenses…", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFocused)
                .onChange(of: text) { HapticManager.light() }

            if !text.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { text = "" }
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.tertiaryBg)
        )
        .animation(.easeOut(duration: 0.2), value: text.isEmpty)
    }
}
