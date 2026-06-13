import SwiftUI

struct ExpenseInputView: View {
    let isProcessing: Bool
    let onSubmit: (String) async -> Bool
    var placeholder: String = "spent 45 at whole foods…"
    var focusTrigger: Int = 0
    var onCameraTap: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var inputText = ""
    @State private var showCheckmark = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                placeholder,
                text: $inputText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(AppColors.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { handleSubmit() }
            .onChange(of: isFocused) {
                onFocusChange?(isFocused)
            }

            if onCameraTap != nil {
                Button {
                    isFocused = false
                    onCameraTap?()
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }

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
        .onChange(of: focusTrigger) {
            isFocused = true
        }
    }

    private func handleSubmit() {
        let rawInput = inputText.trimmingCharacters(in: .whitespaces)
        guard !rawInput.isEmpty else { return }

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
        if showCheckmark { return AppColors.success }
        return Color.blue
    }
}
