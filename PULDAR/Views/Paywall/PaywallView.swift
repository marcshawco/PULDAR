import SwiftUI
import StoreKit

/// Premium paywall sheet with playful lock animation.
///
/// Triggered when the user exhausts 10 free monthly inputs.
/// Offers monthly or yearly Pro subscriptions.
struct PaywallView: View {
    enum Context {
        case standard
        case onboardingTrial
    }

    @Environment(StoreKitManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    let context: Context
    var onFinished: (() -> Void)? = nil

    @State private var lockWobble: Double = 0
    @State private var isUnlocked = false
    @State private var featuresAppeared = false
    @State private var selectedPlan: StoreKitManager.ProPlan = .yearly
    @ScaledMetric(relativeTo: .body) private var heroCircleSize = 120
    @ScaledMetric(relativeTo: .title) private var heroLockSize = 52

    init(context: Context = .standard, onFinished: (() -> Void)? = nil) {
        self.context = context
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760 || proxy.size.width < 390

            ScrollView(showsIndicators: false) {
                VStack(spacing: compact ? 20 : 28) {
                    Spacer(minLength: compact ? 12 : 20)

                    // ── Animated Lock Icon ─────────────────────────────────────
                    ZStack {
                        Circle()
                            .fill(AppColors.accent.opacity(0.06))
                            .frame(width: heroCircleSize, height: heroCircleSize)

                        Image(systemName: isUnlocked ? "lock.open" : "lock")
                            .font(.system(size: heroLockSize, weight: .ultraLight))
                            .foregroundStyle(isUnlocked ? .green : AppColors.accent)
                            .rotationEffect(.degrees(lockWobble))
                            .symbolEffect(.bounce, value: isUnlocked)
                    }
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.8)
                            .repeatForever(autoreverses: true)
                        ) {
                            lockWobble = 8
                        }
                    }

                    // ── Headline ───────────────────────────────────────────────
                    VStack(spacing: 6) {
                        Text(context == .onboardingTrial ? "Start Your 14-Day Trial" : "PULDAR Pro")
                            .font(compact ? .title3.bold() : .title2.bold())
                            .multilineTextAlignment(.center)

                        Text(
                            context == .onboardingTrial
                            ? "Get full access right away, or continue with the restricted free version and upgrade later."
                            : "Unlimited AI expense tracking"
                        )
                        .font(compact ? .footnote : .subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                    }

                    // ── Feature List ───────────────────────────────────────────
                    VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                        featureRow(icon: "sparkles",         text: "Unlimited AI-powered entries", compact: compact)
                        featureRow(icon: "repeat",           text: "Recurring monthly transactions", compact: compact)
                        featureRow(icon: "arrow.triangle.2.circlepath", text: "Rollover monthly balances", compact: compact)
                        featureRow(icon: "tablecells",       text: "Clean CSV export tools", compact: compact)
                        featureRow(icon: "chart.pie",        text: "Full budget analytics", compact: compact)
                        featureRow(icon: "calendar",         text: "Choose monthly or yearly billing", compact: compact)
                        featureRow(icon: "lock.shield",      text: "100% local & private", compact: compact)
                        if context == .onboardingTrial {
                            featureRow(icon: "gift", text: "14 days free before billing begins", compact: compact)
                        }
                    }
                    .padding(.horizontal, compact ? 20 : 32)
                    .opacity(featuresAppeared ? 1 : 0)
                    .offset(y: featuresAppeared ? 0 : 12)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                            featuresAppeared = true
                        }
                    }

                    Spacer(minLength: compact ? 8 : 12)

                    // ── Purchase Button ────────────────────────────────────────
                    VStack(spacing: 12) {
                        if !store.proProducts.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(StoreKitManager.ProPlan.allCases) { plan in
                                    subscriptionOption(plan: plan, compact: compact)
                                }
                            }
                            .padding(.horizontal, compact ? 20 : 32)

                            Button {
                                Task {
                                    await store.purchase(plan: selectedPlan)
                                    if store.isPro {
                                        withAnimation(.spring(duration: 0.5)) { isUnlocked = true }
                                        try? await Task.sleep(for: .seconds(1.2))
                                        finishFlow()
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if store.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    }
                                    Text(primaryButtonTitle)
                                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, compact ? 13 : 15)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppColors.accent)
                                )
                                .foregroundStyle(.white)
                            }
                            .disabled(store.isLoading)
                            .padding(.horizontal, compact ? 20 : 32)
                        } else {
                            ProgressView("Loading…")
                        }

                        Button("Restore Purchases") {
                            Task {
                                await store.restorePurchases()
                                if store.isPro {
                                    finishFlow()
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .disabled(store.isLoading)

                        Text(
                            context == .onboardingTrial
                            ? "Free for 14 days, then \(selectedPlan == .yearly ? "$49.99/year" : "$4.99/month"). Cancel anytime in App Store settings before renewal. If you skip, you can still use the limited free version."
                            : "Subscriptions renew automatically until canceled in App Store settings. Cancel anytime before renewal."
                        )
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, compact ? 20 : 32)

                        if context == .onboardingTrial {
                            Button("Continue with Limited Free Version") {
                                finishFlow()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .disabled(store.isLoading)
                        }

                        if let error = store.purchaseError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, compact ? 20 : 32)
                        }
                    }
                    Spacer(minLength: compact ? 12 : 20)
                }
            }
        }
        .interactiveDismissDisabled(context == .onboardingTrial || store.isLoading)
        .task {
            await store.loadProducts()
            await store.checkEntitlement()
            selectedPlan = store.defaultPlan
        }
    }

    // MARK: - Subview

    @ViewBuilder
    private func subscriptionOption(plan: StoreKitManager.ProPlan, compact: Bool) -> some View {
        let isSelected = selectedPlan == plan
        let product = store.product(for: plan)

        Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.marketingTitle)
                            .font(compact ? .subheadline.weight(.semibold) : .headline)
                            .foregroundStyle(AppColors.textPrimary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppColors.accent.opacity(0.14))
                                )
                                .foregroundStyle(AppColors.accent)
                        }
                    }

                    Text(product?.displayPrice ?? plan.marketingPrice)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 18 : 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 12 : 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.secondaryBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? AppColors.accent.opacity(0.55) : Color.clear, lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var primaryButtonTitle: String {
        if context == .onboardingTrial {
            return "Start 14-Day Free Trial"
        }

        let plan = selectedPlan
        let price = store.product(for: plan)?.displayPrice ?? plan.marketingPrice
        return "Start \(plan.marketingTitle) for \(price)"
    }

    private func featureRow(icon: String, text: String, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: compact ? 13 : 14, weight: .thin))
                .foregroundStyle(AppColors.accent)
                .frame(width: 22)

            Text(text)
                .font(compact ? .footnote : .subheadline)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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
