import SwiftUI

/// First-run model onboarding.
///
/// Explains the on-device model behavior and ensures the user confirms
/// download if they are not on Wi-Fi.
struct ModelDownloadOnboardingView: View {
    @Environment(LLMService.self) private var llmService
    @Environment(NetworkMonitor.self) private var networkMonitor

    let onCompleted: () -> Void

    @State private var showCellularConfirm = false

    private var isBusy: Bool {
        switch llmService.loadState {
        case .downloading, .loading:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Down Local AI")
                    .font(.largeTitle.bold())

                Text("PULDAR runs AI fully on-device. We download a one-time model so your expense text never leaves your phone.")
                    .font(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(icon: "lock.shield", text: "Private: processing stays local")
                    infoRow(icon: "icloud.and.arrow.down", text: "One-time download (~400 MB)")
                    infoRow(icon: "wifi", text: networkMonitor.connectionLabel)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.secondaryBg)
                )
                .frame(maxWidth: .infinity, alignment: .center)

                modelStatus

                Spacer()

                Button(action: startDownloadTapped) {
                    Text(primaryButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(buttonColor)
                        )
                        .foregroundStyle(.white)
                }
                .disabled(primaryButtonDisabled)

                Text("If you continue on cellular data, charges may apply.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .interactiveDismissDisabled(true)
            .confirmationDialog(
                "You are not on Wi-Fi",
                isPresented: $showCellularConfirm
            ) {
                Button("Download on Cellular", role: .destructive) {
                    Task { await beginDownload() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Continue downloading the model over cellular data?")
            }
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch llmService.loadState {
        case .idle:
            EmptyView()
        case .downloading(let progress):
            let safeProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
            if safeProgress < 0.995 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: safeProgress)
                        .tint(AppColors.accent)
                    Text("Downloading… \(Int(safeProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Preparing model…")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        case .ready:
            Label("Model ready", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var primaryButtonTitle: String {
        if case .ready = llmService.loadState {
            return "Continue"
        }
        if !networkMonitor.isConnected {
            return "Waiting for internet"
        }
        if networkMonitor.isOnWiFi {
            return isBusy ? "Downloading…" : "Download on Wi-Fi"
        }
        return isBusy ? "Downloading…" : "Download using cellular data"
    }

    private var primaryButtonDisabled: Bool {
        if case .ready = llmService.loadState {
            return false
        }
        return isBusy || !networkMonitor.isConnected
    }

    private var buttonColor: Color {
        primaryButtonDisabled ? Color.gray.opacity(0.6) : AppColors.accent
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(AppColors.textPrimary)
    }

    private func startDownloadTapped() {
        if case .ready = llmService.loadState {
            onCompleted()
            return
        }

        guard networkMonitor.isConnected else { return }

        if networkMonitor.isOnWiFi {
            Task { await beginDownload() }
        } else {
            showCellularConfirm = true
        }
    }

    private func beginDownload() async {
        await llmService.loadModel()
        if case .ready = llmService.loadState {
            onCompleted()
        }
    }
}
