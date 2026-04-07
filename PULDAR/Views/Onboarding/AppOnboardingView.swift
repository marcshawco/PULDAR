import SwiftUI

struct AppOnboardingView: View {
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
            title: "Everything Is Ready To Use",
            subtitle: "Jump in with the full PULDAR experience.",
            detail: "Recurring expenses, rollover budgets, exports, receipt scanning, and unlimited entries are all included. Set your budget, add your first expense, and make the app your own.",
            symbol: "checkmark.seal.fill",
            accent: AppColors.accent,
            highlights: [
                "Unlimited entries",
                "Recurring expenses and rollover",
                "CSV and JSON exports included"
            ]
        ),
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isCompactHeight = proxy.size.height < 760
                let headerSpacing: CGFloat = isCompactHeight ? 2 : 4
                let verticalSpacing: CGFloat = isCompactHeight ? 16 : 24
                let horizontalPadding: CGFloat = isCompactHeight ? 16 : 20
                let verticalPadding: CGFloat = isCompactHeight ? 16 : 24

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

                    VStack(spacing: verticalSpacing) {
                        header(spacing: headerSpacing, compact: isCompactHeight)

                        TabView(selection: $currentPage) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                                pageCard(page, compact: isCompactHeight)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        pageIndicator

                        ctaRow(compact: isCompactHeight)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                }
            }
            .interactiveDismissDisabled(true)
        }
    }

    private func header(spacing: CGFloat, compact: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: spacing) {
                Text("Welcome to PULDAR")
                    .font(compact ? .largeTitle.weight(.bold) : .largeTitle.bold())

                Text("A calmer way to track spending.")
                    .font(compact ? .footnote : .subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
    }

    private func pageCard(_ page: OnboardingPage, compact: Bool) -> some View {
        let cardSpacing: CGFloat = compact ? 16 : 22
        let cardPadding: CGFloat = compact ? 18 : 24
        let heroSpacing: CGFloat = compact ? 14 : 18
        let textSpacing: CGFloat = compact ? 8 : 10
        let highlightSpacing: CGFloat = compact ? 8 : 12
        let highlightVerticalPadding: CGFloat = compact ? 10 : 12
        let iconSize: CGFloat = compact ? 34 : 42

        return VStack(alignment: .leading, spacing: cardSpacing) {
            VStack(alignment: .leading, spacing: heroSpacing) {
                Image(systemName: page.symbol)
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(page.accent)

                VStack(alignment: .leading, spacing: textSpacing) {
                    Text(page.title)
                        .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.subtitle)
                        .font(compact ? .subheadline.weight(.medium) : .headline.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.detail)
                        .font(compact ? .callout : .body)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(cardPadding)
            .background {
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

                    Circle()
                        .fill(page.accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                        .offset(x: 22, y: -14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(page.accent.opacity(0.18), lineWidth: 1)
                }
            }

            VStack(spacing: highlightSpacing) {
                ForEach(page.highlights, id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: compact ? 14 : 16, weight: .semibold))
                            .foregroundStyle(page.accent)

                        Text(item)
                            .font(compact ? .footnote.weight(.medium) : .subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, highlightVerticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.secondaryBg)
                    )
                }
            }

            if currentPage == pages.count - 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next up: your first entry")
                        .font((compact ? Font.caption : .footnote).weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Finish onboarding and you’ll land directly in the app with every feature available.")
                        .font(compact ? .caption : .footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 0 : 8)
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

    private func ctaRow(compact: Bool) -> some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button("Back") {
                    currentPage = max(currentPage - 1, 0)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 13 : 15)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.secondaryBg)
                )
            }

            Button(currentPage == pages.count - 1 ? "Get Started" : "Continue") {
                if currentPage == pages.count - 1 {
                    onCompleted()
                } else {
                    currentPage += 1
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 13 : 15)
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
