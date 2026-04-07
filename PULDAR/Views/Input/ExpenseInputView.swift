import SwiftUI

/// The primary user intent — a single, prominent text input.
///
/// Features:
/// - Spring-animated submit button (arrow → checkmark on success).
/// - Processing spinner while the LLM parses.
/// - Optional disabled state with shake feedback.
struct ExpenseInputView: View {
    let isProcessing: Bool
    let isLocked: Bool
    let onSubmit: (String) async -> Bool
    var focusTrigger: Int = 0
    var onLockedTap: (() -> Void)? = nil
    var onCameraTap: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var inputText = ""
    @State private var showCheckmark = false
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var actionButtonSize = 40

    var body: some View {
        HStack(spacing: 10) {
            // ── Text Field ─────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.caption.weight(.light))
                    .foregroundStyle(AppColors.textTertiary)

                TextField(
                    isLocked ? "Input unavailable right now" : "spent 45 at whole foods, or got 20 refund…",
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
                            .font(.caption.weight(.regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                if isLocked {
                    handleLockedInteraction()
                }
            }
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

            Button {
                if isLocked {
                    handleLockedInteraction()
                    return
                }
                isFocused = false
                onCameraTap?()
            } label: {
                Image(systemName: "camera")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .background(
                        Circle()
                            .fill(AppColors.secondaryBg)
                    )
                    .foregroundStyle(isLocked ? AppColors.textTertiary : AppColors.accent)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            // ── Submit Button ──────────────────────────────────────────
            Button(action: handleSubmit) {
                Group {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: showCheckmark ? "checkmark" : "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: actionButtonSize, height: actionButtonSize)
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
        .onChange(of: focusTrigger) {
            guard !isLocked else { return }
            isFocused = true
        }
    }

    // MARK: - Actions

    private func handleSubmit() {
        let rawInput = inputText.trimmingCharacters(in: .whitespaces)
        guard !rawInput.isEmpty else { return }

        if isLocked {
            handleLockedInteraction()
            return
        }

        inputText = ""
        Task {
            let success = await onSubmit(rawInput)
            if success {
                withAnimation(.spring(duration: 0.4, bounce: 0.5)) {
                    showCheckmark = true
                }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.spring(duration: 0.3)) {
                    showCheckmark = false
                }
            } else {
                inputText = rawInput
            }
        }
    }

    // MARK: - Colours

    private var buttonColor: Color {
        if isLocked { return .gray.opacity(0.5) }
        if showCheckmark { return .green }
        return AppColors.accent
    }

    private func handleLockedInteraction() {
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
        onLockedTap?()
    }
}
