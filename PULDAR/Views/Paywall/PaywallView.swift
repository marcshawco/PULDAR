import SwiftUI

/// Compatibility screen retained so any legacy navigation still lands on a
/// friendly "everything is included" message instead of a purchase flow.
struct PaywallView: View {
    enum Context {
        case standard
        case onboardingTrial
    }

    @Environment(\.dismiss) private var dismiss

    let context: Context
    var onFinished: (() -> Void)? = nil

    init(context: Context = .standard, onFinished: (() -> Void)? = nil) {
        self.context = context
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: 8) {
                    Text("Everything Is Included")
                        .font(.title2.bold())

                    Text("PULDAR is now fully free to use, so recurring expenses, exports, rollover budgets, receipt scanning, and unlimited entries are all available.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Button(context == .onboardingTrial ? "Get Started" : "Done") {
                    finishFlow()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accent)
                )
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func finishFlow() {
        if let onFinished {
            onFinished()
        } else {
            dismiss()
        }
    }
}
