import SwiftUI

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

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                "spent 45 at whole foods…",
                text: $inputText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(AppColors.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($isFocused)
            .disabled(isLocked)
            .submitLabel(.done)
            .onSubmit { if !isLocked { handleSubmit() } }
            .onChange(of: isFocused) {
                onFocusChange?(isFocused)
            }

            Button {
                if isLocked {
                    handleLockedInteraction()
                    return
                }
                isFocused = false
                onCameraTap?()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isLocked ? AppColors.textTertiary : AppColors.textTertiary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            Button(action: handleSubmit) {
                Group {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: showCheckmark ? "checkmark" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 32, height: 32)
                .background(Circle().fill(buttonColor))
                .foregroundStyle(.white)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
            .scaleEffect(showCheckmark ? 1.14 : 1.0)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: showCheckmark)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(AppColors.secondaryBg)
        .offset(x: shakeOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            if isLocked { handleLockedInteraction() }
        }
        .onChange(of: focusTrigger) {
            guard !isLocked else { return }
            isFocused = true
        }
    }

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
            if !success {
                inputText = rawInput
            }
        }

        withAnimation(.spring(duration: 0.4, bounce: 0.5)) {
            showCheckmark = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.3)) {
                showCheckmark = false
            }
        }
    }

    private var buttonColor: Color {
        if isLocked { return AppColors.textTertiary.opacity(0.5) }
        if showCheckmark { return AppColors.success }
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
