import SwiftUI

/// The primary user intent — a single, prominent text input.
///
/// Features:
/// - Spring-animated submit button (arrow → checkmark on success).
/// - Processing spinner while the LLM parses.
/// - Disabled state for paywall lock with a playful shake.
struct ExpenseInputView: View {
    @Binding var inputText: String
    let isProcessing: Bool
    let isLocked: Bool
    let onSubmit: () -> Void

    @State private var showCheckmark = false
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            // ── Text Field ─────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 14, weight: .ultraLight))
                    .foregroundStyle(AppColors.textTertiary)

                TextField(
                    isLocked ? "Free limit reached — upgrade to Pro" : "spent 45 at whole foods…",
                    text: $inputText
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFocused)
                .disabled(isLocked)
                .submitLabel(.done)
                .onSubmit { if !isLocked { handleSubmit() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.secondaryBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isFocused ? AppColors.accent.opacity(0.4) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .offset(x: shakeOffset)

            // ── Submit Button ──────────────────────────────────────────
            Button(action: handleSubmit) {
                Group {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: showCheckmark ? "checkmark" : "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(buttonColor)
                )
                .foregroundStyle(.white)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
            .scaleEffect(isProcessing ? 0.95 : 1.0)
            .animation(.spring(duration: 0.3), value: isProcessing)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func handleSubmit() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        if isLocked {
            // Playful shake animation when locked
            withAnimation(.spring(duration: 0.08).repeatCount(4, autoreverses: true)) {
                shakeOffset = 8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                shakeOffset = 0
            }
            HapticManager.warning()
            return
        }

        onSubmit()

        // Arrow → checkmark animation
        withAnimation(.spring(duration: 0.4, bounce: 0.5)) {
            showCheckmark = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.3)) {
                showCheckmark = false
            }
        }
    }

    // MARK: - Colours

    private var buttonColor: Color {
        if isLocked { return .gray.opacity(0.5) }
        if showCheckmark { return .green }
        return AppColors.accent
    }
}
