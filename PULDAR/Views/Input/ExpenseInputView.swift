import SwiftUI

/// The primary user intent — a single, prominent text input.
///
/// Features:
/// - Spring-animated submit button (arrow → checkmark on success).
/// - Processing spinner while the LLM parses.
/// - Disabled state for paywall lock with a playful shake.
struct ExpenseInputView: View {
    let isProcessing: Bool
    let isLocked: Bool
    let onSubmit: (String) async -> Bool
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var inputText = ""
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
                    isLocked ? "Free limit reached — upgrade to Pro" : "spent 45 at whole foods, or got 20 refund…",
                    text: $inputText
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($isFocused)
                .disabled(isLocked)
                .submitLabel(.done)
                .onSubmit { if !isLocked { handleSubmit() } }
                .onChange(of: isFocused) {
                    onFocusChange?(isFocused)
                }

                if isFocused {
                    Button {
                        isFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
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
            .animation(.easeOut(duration: 0.2), value: isFocused)

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
        .padding(.bottom, isFocused ? 42 : 0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    // MARK: - Actions

    private func handleSubmit() {
        let rawInput = inputText.trimmingCharacters(in: .whitespaces)
        guard !rawInput.isEmpty else { return }

        if isLocked {
            Task { @MainActor in
                let steps: [CGFloat] = [8, -8, 6, -6, 0]
                for value in steps {
                    withAnimation(.easeInOut(duration: 0.045)) {
                        shakeOffset = value
                    }
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
            HapticManager.warning()
            return
        }

        inputText = ""
        Task {
            let success = await onSubmit(rawInput)
            if !success {
                inputText = rawInput
            }
        }

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
