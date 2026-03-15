import SwiftUI

struct AppOnboardingView: View {
    @Environment(StoreKitManager.self) private var store

    private struct OnboardingPage: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let detail: String
        let symbol: String
        let accent: Color
        let highlights: [String]
    }

    let onCompleted: () -> Void

    @State private var currentPage = 0
    @State private var showTrialOffer = false

    private let pages: [OnboardingPage] = [
        .init(
            title: "Budgeting That Feels Effortless",
            subtitle: "Track spending with plain language instead of manual forms.",
            detail: "PULDAR turns quick text like \"spent 45 at whole foods\" into organized entries, live balances, and a cleaner monthly picture.",
            symbol: "sparkles.rectangle.stack",
            accent: AppColors.accent,
            highlights: [
                "Log expenses in seconds",
                "See what is left this month",
                "Keep everything on-device"
            ]
        ),
        .init(
            title: "Use It The Way You Already Think",
            subtitle: "Type it naturally or scan a receipt.",
            detail: "You can add expenses by typing one quick sentence or using the camera. PULDAR reads the merchant, amount, and category, then saves it into the right budget.",
            symbol: "camera.viewfinder",
            accent: AppColors.bucketFundamentals,
            highlights: [
                "Type: \"coffee 5.50\"",
                "Scan long receipts with the camera",
                "Review everything later in History"
            ]
        ),
        .init(
            title: "Your Money Lives In Three Budgets",
            subtitle: "Fundamentals, Fun, and Future keep spending simple.",
            detail: "Instead of forcing dozens of categories up front, PULDAR helps you stay oriented around needs, wants, and savings so your budget stays easy to maintain.",
            symbol: "chart.pie.fill",
            accent: AppColors.bucketFuture,
            highlights: [
                "Fundamentals = needs and bills",
                "Fun = lifestyle and wants",
                "Future = savings, debt, and investing"
            ]
        ),
        .init(
            title: "Built For Daily Check-Ins",
            subtitle: "The widget keeps your balances visible without opening the app.",
            detail: "Add the PULDAR widget to your Home Screen to keep your three remaining balances top-of-mind. It is a fast daily glance that helps you stay intentional before you spend.",
            symbol: "rectangle.grid.2x2.fill",
            accent: AppColors.bucketFun,
            highlights: [
                "See remaining balances at a glance",
                "Make better decisions before spending",
                "Open the app only when you need detail"
            ]
        ),
        .init(
            title: "Try Pro First",
            subtitle: "Start with 14 days free, then decide what fits.",
            detail: "We’ll offer the trial immediately so high-intent users can unlock the full experience right away. If you pass for now, you will still get a restricted freemium version to keep building conviction.",
            symbol: "gift.fill",
            accent: AppColors.accent,
            highlights: [
                "14 full days of Pro access",
                "Yearly saves money vs monthly",
                "Skip now and keep using free"
            ]
        ),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        AppColors.background,
                        AppColors.secondaryBg,
                        AppColors.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    header

                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            pageCard(page)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    pageIndicator

                    ctaRow
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .interactiveDismissDisabled(true)
            .sheet(isPresented: $showTrialOffer) {
                PaywallView(context: .onboardingTrial) {
                    showTrialOffer = false
                    onCompleted()
                }
                .environment(store)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to PULDAR")
                    .font(.largeTitle.bold())

                Text("A calmer way to track spending.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
    }

    private func pageCard(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                page.accent.opacity(0.18),
                                AppColors.secondaryBg
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(page.accent.opacity(0.18), lineWidth: 1)
                    )

                Circle()
                    .fill(page.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .offset(x: 22, y: -14)

                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(page.accent)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(page.title)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(page.subtitle)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(page.detail)
                            .font(.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }

            VStack(spacing: 12) {
                ForEach(page.highlights, id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(page.accent)

                        Text(item)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.secondaryBg)
                    )
                }
            }

            if currentPage == pages.count - 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next up: trial or freemium")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("We’ll present the 14-day trial right away. If you skip it, you will still land in the limited free version and can upgrade later.")
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentPage ? AppColors.accent : AppColors.textTertiary.opacity(0.25))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.3), value: currentPage)
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button("Back") {
                    currentPage = max(currentPage - 1, 0)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.secondaryBg)
                )
            }

            Button(currentPage == pages.count - 1 ? "See Trial Options" : "Continue") {
                if currentPage == pages.count - 1 {
                    showTrialOffer = true
                } else {
                    currentPage += 1
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.accent)
            )
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    AppOnboardingView(onCompleted: {})
}
