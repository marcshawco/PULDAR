import SwiftUI

struct AppOnboardingView: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(AppPreferences.self) private var appPreferences

    let onCompleted: () -> Void

    @State private var step = 0
    @State private var incomeText = ""
    @State private var draftAlloc: [String: Double] = [
        "Fundamentals": 0.50, "Fun": 0.30, "Future": 0.20
    ]
    @FocusState private var incomeFieldFocused: Bool

    private let totalSteps = 5
    private let quickPickAmounts = [3000, 4200, 5200, 6500, 8000, 10000]

    private var draftIncome: Double {
        Double(incomeText) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressHairline
            stepContent
            bottomButton
        }
        .background(AppColors.background.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Text("← Back")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("PULDAR")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(2.2)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Text(String(format: "%02d / %02d", step + 1, totalSteps))
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.8)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var progressHairline: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(AppColors.border)
                Rectangle()
                    .fill(AppColors.textPrimary)
                    .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
                    .animation(.easeInOut(duration: 0.4), value: step)
            }
        }
        .frame(height: 1)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        GeometryReader { proxy in
            ScrollView {
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: incomeStep
                    case 2: ruleStep
                    case 3: mixStep
                    case 4: privacyStep
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, 28)
                .frame(
                    maxWidth: .infinity,
                    minHeight: shouldCenterStepContent ? proxy.size.height : 0,
                    alignment: shouldCenterStepContent ? .leading : .topLeading
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var shouldCenterStepContent: Bool {
        step == 2
    }

    // MARK: Step 0 — Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome")
                .font(.system(size: 11, weight: .bold))
                .kerning(2.2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 60)
                .padding(.bottom, 24)

            Text("Budget,\nsimply.")
                .font(.system(size: 56, weight: .ultraLight))
                .tracking(-1.7)
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(-4)
                .padding(.bottom, 36)

            Divider()
                .padding(.bottom, 28)

            Text("Three buckets. One rule.\nA lifetime of clarity.\nNo bank linking. No accounts.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step 1 — Income

    private var incomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Step 01 — Income")
                .font(.system(size: 11, weight: .bold))
                .kerning(2.2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 40)
                .padding(.bottom, 18)

            Text("How much do\nyou take home?")
                .font(.system(size: 34, weight: .ultraLight))
                .tracking(-0.7)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, 28)

            Text("Monthly, after tax. You can change this anytime.")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.bottom, 32)

            Divider()

            VStack(spacing: 10) {
                Text("Per month")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(2)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 32)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(AppColors.textSecondary)

                    TextField("0", text: $incomeText)
                        .font(.system(size: 56, weight: .ultraLight))
                        .tracking(-2)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .focused($incomeFieldFocused)
                        .monospacedDigit()
                        .frame(maxWidth: 200)
                }

                Rectangle()
                    .fill(AppColors.textPrimary.opacity(0.4))
                    .frame(width: 200, height: 1)

                Text("Tap to edit")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            Divider()

            Text("Quick pick")
                .font(.system(size: 10, weight: .bold))
                .kerning(2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 24)
                .padding(.bottom, 14)

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 10) {
                ForEach(quickPickAmounts, id: \.self) { amount in
                    Button {
                        incomeText = "\(amount)"
                    } label: {
                        Text("$\(amount.formatted())")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(
                                draftIncome == Double(amount)
                                ? Color.white
                                : AppColors.textPrimary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        draftIncome == Double(amount)
                                        ? AppColors.textPrimary
                                        : AppColors.secondaryBg
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step 2 — The Rule

    private var ruleStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Step 02 — The Rule")
                .font(.system(size: 11, weight: .bold))
                .kerning(2.2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 32)
                .padding(.bottom, 14)

            Text("Three buckets.\nOne life.")
                .font(.system(size: 30, weight: .ultraLight))
                .tracking(-0.6)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, 24)

            Divider()

            ForEach(Array(bucketRuleData.enumerated()), id: \.element.name) { index, item in
                HStack(alignment: .center, spacing: 16) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 9, weight: .bold))
                        .kerning(2)
                        .foregroundStyle(AppColors.textTertiary)

                    Rectangle()
                        .fill(item.color)
                        .frame(width: 3, height: 32)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 20, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(item.desc)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(item.pct)%")
                            .font(.system(size: 28, weight: .ultraLight))
                            .monospacedDigit()
                            .tracking(-0.9)
                            .foregroundStyle(AppColors.textPrimary)

                        if draftIncome > 0 {
                            Text((draftIncome * Double(item.pct) / 100).formattedCurrency(code: appPreferences.currencyCode))
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(AppColors.textTertiary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 24)

                if index < bucketRuleData.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bucketRuleData: [(name: String, desc: String, pct: Int, color: Color)] {
        [
            ("Fundamentals", "Rent, food, utilities. Needs.", Int(round((draftAlloc["Fundamentals"] ?? 0.5) * 100)), AppColors.bucketFundamentals),
            ("Fun", "Dining, travel, leisure. Wants.", Int(round((draftAlloc["Fun"] ?? 0.3) * 100)), AppColors.bucketFun),
            ("Future", "Savings, investing. Growth.", Int(round((draftAlloc["Future"] ?? 0.2) * 100)), AppColors.bucketFuture),
        ]
    }

    // MARK: Step 3 — Mix

    private var mixStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Step 04 — Mix")
                .font(.system(size: 11, weight: .bold))
                .kerning(2.2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 40)
                .padding(.bottom, 28)

            Text("Choose\nyour mix.")
                .font(.system(size: 38, weight: .ultraLight))
                .tracking(-1)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, 44)

            Divider()

            ForEach(presets) { preset in
                Button {
                    if let values = preset.allocValues {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            draftAlloc = values
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Circle()
                            .strokeBorder(
                                isPresetSelected(preset) ? AppColors.textPrimary : AppColors.border,
                                lineWidth: 1.5
                            )
                            .frame(width: 14, height: 14)
                            .overlay {
                                if isPresetSelected(preset) {
                                    Circle()
                                        .fill(AppColors.textPrimary)
                                        .frame(width: 6, height: 6)
                                }
                            }

                        Text(preset.name)
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.1)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 72, alignment: .leading)
                            .layoutPriority(1)

                        Spacer()

                        if let values = preset.displayValues(alloc: draftAlloc, income: draftIncome) {
                            HStack(spacing: 12) {
                                presetColumn(pct: values.fundPct, amount: values.fundAmt, color: AppColors.bucketFundamentals)
                                presetColumn(pct: values.funPct, amount: values.funAmt, color: AppColors.bucketFun)
                                presetColumn(pct: values.futPct, amount: values.futAmt, color: AppColors.bucketFuture)
                            }
                        }
                    }
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)

                Divider()
            }

            if draftIncome > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    Text("You'll start with")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)

                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(BudgetBucket.allCases) { bucket in
                                let pct = draftAlloc[bucket.rawValue] ?? 0
                                if pct > 0 {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(bucket.color)
                                        .frame(width: max(geo.size.width * pct - 1, 0))
                                }
                            }
                        }
                    }
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(.top, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetColumn(pct: Int, amount: Double, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(pct)%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
            if amount > 0 {
                Text(amount.formattedCurrency(code: appPreferences.currencyCode))
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary)
                    .monospacedDigit()
            }
        }
        .frame(width: 60, alignment: .trailing)
    }

    // MARK: Step 4 — Privacy

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Step 05 — Privacy")
                .font(.system(size: 11, weight: .bold))
                .kerning(2.2)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 56)
                .padding(.bottom, 28)

            Text("On device.")
                .font(.system(size: 52, weight: .ultraLight))
                .tracking(-1.8)
                .foregroundStyle(AppColors.textPrimary)
            Text("Always.")
                .font(.system(size: 52, weight: .ultraLight))
                .tracking(-1.8)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.bottom, 36)

            Divider()
                .padding(.bottom, 28)

            Text("PULDAR parses your entries with a small language model that runs entirely on your phone. Your data never leaves the device.")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(5)
                .padding(.bottom, 40)

            ForEach(Array(privacyPillars.enumerated()), id: \.element.key) { index, pillar in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(pillar.num)
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pillar.key)
                            .font(.system(size: 18, weight: .medium))
                            .tracking(-0.3)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(pillar.value)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, 20)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Includes")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                    Text("PULDAR Mini · 1.2 GB")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(AppColors.textPrimary)
                }
                Spacer()
                Text("~3 min · Wi-Fi")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.top, 32)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let privacyPillars = [
        (num: "i.", key: "No accounts", value: "Nothing to sign up for. Ever."),
        (num: "ii.", key: "No tracking", value: "Zero analytics. Zero servers."),
        (num: "iii.", key: "Yours alone", value: "Export or delete anytime."),
    ]

    // MARK: - Bottom Button

    private var bottomButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if step == totalSteps - 1 {
                    finalizeAndComplete()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
                }
            } label: {
                Text(buttonLabel)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(2.4)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.textPrimary)
                    .foregroundStyle(AppColors.background)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
    }

    private var buttonLabel: String {
        switch step {
        case 0: return "Begin →"
        case totalSteps - 1: return "Download & start →"
        default: return "Continue →"
        }
    }

    // MARK: - Presets

    private struct OnboardingPreset: Identifiable {
        let id = UUID()
        let name: String
        let allocValues: [String: Double]?

        struct DisplayValues {
            let fundPct: Int, funPct: Int, futPct: Int
            let fundAmt: Double, funAmt: Double, futAmt: Double
        }

        func displayValues(alloc: [String: Double], income: Double) -> DisplayValues? {
            let vals = allocValues ?? alloc
            let f = vals["Fundamentals"] ?? 0
            let fu = vals["Fun"] ?? 0
            let ft = vals["Future"] ?? 0
            return DisplayValues(
                fundPct: Int(round(f * 100)),
                funPct: Int(round(fu * 100)),
                futPct: Int(round(ft * 100)),
                fundAmt: income * f,
                funAmt: income * fu,
                futAmt: income * ft
            )
        }
    }

    private let presets: [OnboardingPreset] = [
        .init(name: "Classic", allocValues: ["Fundamentals": 0.50, "Fun": 0.30, "Future": 0.20]),
        .init(name: "Saver", allocValues: ["Fundamentals": 0.50, "Fun": 0.20, "Future": 0.30]),
        .init(name: "Lean", allocValues: ["Fundamentals": 0.60, "Fun": 0.20, "Future": 0.20]),
        .init(name: "Custom", allocValues: nil),
    ]

    private func isPresetSelected(_ preset: OnboardingPreset) -> Bool {
        guard let values = preset.allocValues else {
            return !presets.compactMap(\.allocValues).contains(where: { vals in
                BudgetBucket.allCases.allSatisfy { abs((draftAlloc[$0.rawValue] ?? 0) - (vals[$0.rawValue] ?? 0)) < 0.001 }
            })
        }
        return BudgetBucket.allCases.allSatisfy {
            abs((draftAlloc[$0.rawValue] ?? 0) - (values[$0.rawValue] ?? 0)) < 0.001
        }
    }

    // MARK: - Finalize

    private func finalizeAndComplete() {
        if draftIncome > 0 {
            budgetEngine.monthlyIncome = draftIncome
        }
        budgetEngine.setPercentages(draftAlloc)
        onCompleted()
    }
}
