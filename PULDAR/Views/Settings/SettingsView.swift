import SwiftUI
import SwiftData

/// Settings sheet — income, allocation, recurring expenses, and data controls.
struct SettingsView: View {
    private static let privacyPolicyURL = URL(string: "https://shawhause.com/puldar-privacy.html")!

    private enum IncomeInputMode: String, CaseIterable, Identifiable {
        case monthly
        case hourly

        var id: String { rawValue }
        var title: String {
            switch self {
            case .monthly: return "Monthly"
            case .hourly: return "Hourly"
            }
        }
    }

    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(DiagnosticLogger.self) private var diagnosticLogger
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]
    @Query(sort: \RecurringExpense.createdAt, order: .reverse)
    private var recurringExpenses: [RecurringExpense]

    @State private var incomeText: String = ""
    @State private var hourlyPayText: String = ""
    @State private var hoursPerWeekText: String = ""
    @FocusState private var focusedIncomeField: IncomeFocusField?
    @State private var draftPercentages: [String: Double] = [:]
    @State private var showAddRecurringSheet = false
    @State private var newRecurringName = ""
    @State private var newRecurringAmount = ""
    @State private var newRecurringBucket: BudgetBucket = .fun
    @State private var addRecurringError: String?
    @State private var selectedAllocationPreset: AllocationPreset = .custom
    @State private var showZeroFunWarning = false
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteAllAlert = false
    @State private var showBudgetAllocationInfo = false
    @State private var selectedBudgetInfoBucket: BudgetBucket?
    @State private var showOnboardingReplay = false
    @AppStorage("appThemeMode") private var appThemeMode = "system"
    @State private var selectedAppIcon: AppIconVariant = .colorOnWhite
    @State private var shareSheetURL: SharedFile?
    @Environment(\.openURL) private var openURL
    @AppStorage("incomeInputMode") private var incomeInputModeRaw = IncomeInputMode.monthly.rawValue
    @AppStorage("hourlyPayRate") private var hourlyPayRate: Double = 0
    @AppStorage("hoursPerWeek") private var hoursPerWeek: Double = 40

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 900 : .infinity
    }

    private enum IncomeFocusField: Hashable {
        case monthlyIncome
        case hourlyPay
        case hoursPerWeek
    }

    private var monthOptions: [Date] {
        let calendar = Calendar.current
        let starts = Set(
            expenses.map {
                calendar.date(
                    from: calendar.dateComponents([.year, .month], from: $0.date)
                ) ?? calendar.startOfDay(for: $0.date)
            }
        )
        let sorted = starts.sorted(by: >)
        if sorted.isEmpty {
            return [calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now]
        }
        return sorted
    }

    var body: some View {
        NavigationStack {
            Form {
                incomeSection
                bucketAllocationSection
                recurringSection
                rolloverSection
                dataExportSection
                languageAndCurrencySection
                appearanceSection
                widgetsSection
                dangerZoneSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .toolbarBackground(AppColors.secondaryBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                if budgetEngine.monthlyIncome > 0 {
                    incomeText = String(format: "%.0f", budgetEngine.monthlyIncome)
                }
                hourlyPayText = String(format: "%.2f", max(hourlyPayRate, 0))
                hoursPerWeekText = String(format: "%.2f", max(hoursPerWeek, 0))
                draftPercentages = currentPercentagesSnapshot()
                selectedAllocationPreset = AllocationPreset.matching(draftPercentages) ?? .custom
                if incomeInputMode == .hourly {
                    recalculateMonthlyIncomeFromHourlyInputs()
                }
                selectedAppIcon = AppIconVariant.current
            }
            .onChange(of: draftPercentages) {
                selectedAllocationPreset = AllocationPreset.matching(draftPercentages) ?? .custom
                if isAllocationValid {
                    saveAndDismiss()
                }
            }
            .sheet(isPresented: $showAddRecurringSheet) {
                NavigationStack {
                    Form {
                        TextField("Name (e.g. Hulu)", text: $newRecurringName)
                            .textInputAutocapitalization(.words)

                        TextField("Monthly amount", text: $newRecurringAmount)
                            .keyboardType(.decimalPad)

                        Picker("Category", selection: $newRecurringBucket) {
                            ForEach(BudgetBucket.allCases) { bucket in
                                Text(recurringBucketLabel(bucket)).tag(bucket)
                            }
                        }
                        .pickerStyle(.segmented)

                        if let addRecurringError {
                            Text(addRecurringError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .navigationTitle("Recurring Expense")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                dismissActiveKeyboard()
                                showAddRecurringSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { addRecurringExpense() }
                        }
                    }
                }
            }
            .sheet(item: $shareSheetURL) { wrapped in
                ShareSheet(items: [wrapped.url])
                    .presentationDetents([.medium, .large])
            }
            .alert("Fun is 0%", isPresented: $showZeroFunWarning) {
                Button("Keep 0%") {
                    saveAndDismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Fun is set to 0%. Are you sure you want to continue?")
            }
            .confirmationDialog(
                "Delete all expenses?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Expenses", role: .destructive) {
                    showDeleteAllAlert = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every expense and recurring expense from this device.")
            }
            .alert("Delete Everything", isPresented: $showDeleteAllAlert) {
                Button("Delete", role: .destructive) {
                    clearAllExpenses()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Budget Allocation", isPresented: $showBudgetAllocationInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Your budget allocation decides how much of your monthly income goes to Fundamentals, Fun, and Future. Setting clear percentages helps you spend with intention and stay on track.")
            }
            .alert(item: $selectedBudgetInfoBucket) { bucket in
                Alert(
                    title: Text(bucket.rawValue),
                    message: Text(bucket.infoExplanation),
                    dismissButton: .default(Text("Got it")) {
                        selectedBudgetInfoBucket = nil
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showOnboardingReplay) {
            AppOnboardingView {
                showOnboardingReplay = false
            }
        }
    }

    // MARK: - Helpers

    private var incomeSection: some View {
        Section {
            Picker("Income Type", selection: incomeInputModeBinding) {
                ForEach(IncomeInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if incomeInputMode == .monthly {
                HStack {
                    Text("$")
                        .foregroundStyle(AppColors.textTertiary)
                    TextField("Monthly income", text: $incomeText)
                        .keyboardType(.decimalPad)
                        .focused($focusedIncomeField, equals: .monthlyIncome)
                        .onChange(of: incomeText) {
                            if let value = Double(incomeText) {
                                budgetEngine.monthlyIncome = value
                            }
                        }
                    if focusedIncomeField != nil {
                        Spacer()
                        Button {
                            dismissActiveKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack {
                    Text("$")
                        .foregroundStyle(AppColors.textTertiary)
                    TextField("Hourly pay", text: $hourlyPayText)
                        .keyboardType(.decimalPad)
                        .focused($focusedIncomeField, equals: .hourlyPay)
                        .onChange(of: hourlyPayText) {
                            recalculateMonthlyIncomeFromHourlyInputs()
                        }
                    if focusedIncomeField != nil {
                        Spacer()
                        Button {
                            dismissActiveKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("hrs")
                        .foregroundStyle(AppColors.textTertiary)
                    TextField("Hours per week", text: $hoursPerWeekText)
                        .keyboardType(.decimalPad)
                        .focused($focusedIncomeField, equals: .hoursPerWeek)
                        .onChange(of: hoursPerWeekText) {
                            recalculateMonthlyIncomeFromHourlyInputs()
                        }
                    if focusedIncomeField != nil {
                        Spacer()
                        Button {
                            dismissActiveKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                LabeledContent("Estimated monthly income") {
                    Text(estimatedMonthlyIncome.formattedCurrency(code: appPreferences.currencyCode))
                        .fontWeight(.semibold)
                }
            }
        } header: {
            Text("Monthly Income")
        } footer: {
            Text(
                incomeInputMode == .monthly
                ? "Base monthly income. Add Income transactions to handle variable month-to-month earnings."
                : "Hourly estimate uses: hourly pay × hours/week × 52 ÷ 12. Add Income transactions for extra variable earnings."
            )
        }
    }

    private var bucketAllocationSection: some View {
        Section {
            Picker("Preset", selection: $selectedAllocationPreset) {
                ForEach(AllocationPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedAllocationPreset) {
                applySelectedPresetIfNeeded()
                HapticManager.selection()
            }

            if budgetEngine.monthlyIncome > 0 {
                dollarPreviewBar
                    .padding(.vertical, 4)
            }

            ForEach(BudgetBucket.allCases) { bucket in
                HStack(spacing: 10) {
                    Circle()
                        .fill(bucket.color)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(bucket.rawValue)
                                .font(.subheadline.weight(.medium))
                            Button {
                                selectedBudgetInfoBucket = bucket
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(bucket.subtitle)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            adjustPercentage(for: bucket, by: -0.01)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppColors.secondaryBg))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(draftPercentage(for: bucket) < 0.01)

                        Text("\(Int(draftPercentage(for: bucket) * 100))%")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .frame(minWidth: 36)

                        Button {
                            adjustPercentage(for: bucket, by: 0.01)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppColors.secondaryBg))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack(spacing: 6) {
                Text("Budget Allocation")
                Button {
                    showBudgetAllocationInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "Total: \(Int(totalDraftPercentage * 100))%. " +
                    (isAllocationValid
                        ? "Tap Done to save."
                        : "Must equal exactly 100% to save.")
                )
                .foregroundStyle(isAllocationValid ? AppColors.textTertiary : AppColors.overspend)

                if budgetEngine.monthlyIncome <= 0 {
                    Text("Enter income above to see dollar amounts.")
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    private var dollarPreviewBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(BudgetBucket.allCases) { bucket in
                        let pct = draftPercentage(for: bucket)
                        if pct > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(bucket.color)
                                .frame(width: max(geo.size.width * pct - 1, 0))
                        }
                    }
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            HStack {
                ForEach(BudgetBucket.allCases) { bucket in
                    if bucket != BudgetBucket.allCases.first { Spacer() }
                    Text(draftBucketBudgetDisplay(for: bucket))
                        .font(.system(size: 10))
                        .foregroundStyle(bucket.color)
                        .monospacedDigit()
                }
            }
        }
    }

    private var recurringSection: some View {
        Section {
            if recurringExpenses.isEmpty {
                Text("No recurring expenses yet.")
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(recurringExpenses) { recurring in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recurring.name)
                                .font(.subheadline.weight(.medium))
                            Text(recurringBucketLabel(recurring.budgetBucket))
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                        }

                        Spacer()

                        Text(recurring.safeAmount.formattedCurrency(code: appPreferences.currencyCode))
                            .font(.subheadline.weight(.semibold))

                        Toggle("", isOn: recurringActiveBinding(for: recurring.id))
                            .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteRecurringExpenses)
            }

            Button {
                newRecurringName = ""
                newRecurringAmount = ""
                newRecurringBucket = .fun
                addRecurringError = nil
                showAddRecurringSheet = true
            } label: {
                Label("Add Recurring Expense", systemImage: "plus")
            }
        } header: {
            Text("Recurring Expenses")
        } footer: {
            Text("Recurring expenses are automatically counted every month in budget totals, rollover calculations, and widgets.")
        }
    }

    private var widgetsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Home Screen Snapshot")
                    .font(.headline)

                Text("Add the PULDAR widget to your Home Screen to see your remaining Fundamentals, Fun, and Future balances at a glance.")
                    .foregroundStyle(AppColors.textSecondary)

                Text("On your Home Screen, press and hold, tap Edit, then Add Widget and choose PULDAR.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Widgets")
        }
    }

    private var rolloverSection: some View {
        Section {
            Toggle("Enable Rollover Balances", isOn: rolloverBinding)
                .tint(AppColors.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("How rollover works")
                    .font(.subheadline.weight(.semibold))
                Text("When enabled, unused Fundamentals and Fun money carries into the same bucket next month. Overspent buckets carry nothing forward. Future stays month-to-month so savings goals stay clean.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Rollover Budgets")
        } footer: {
            Text("Allocation percentages and rollover preferences are stored locally and used by the budget engine whenever it calculates remaining balances.")
        }
    }

    private var dataExportSection: some View {
        Section {
            Button {
                exportCurrentMonthCSV()
            } label: {
                Text("Export Current Month (CSV)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                exportCSV(for: expenses, scope: "all_months")
            } label: {
                Text("Export All Data (CSV)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Data Export")
        } footer: {
            Text("Exports are CSV only.")
        }
    }

    private var languageAndCurrencySection: some View {
        Section {
            Picker("Typing Language", selection: Binding(
                get: { appPreferences.inputLanguage },
                set: { appPreferences.inputLanguage = $0 }
            )) {
                ForEach(AppPreferences.InputLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.menu)

            Picker("Display Currency", selection: Binding(
                get: { appPreferences.currencyPreference },
                set: { appPreferences.currencyPreference = $0 }
            )) {
                ForEach(AppPreferences.CurrencyPreference.allCases) { currency in
                    Text(currency.title).tag(currency)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Language & Currency")
        } footer: {
            Text("Plain-text entry supports English, French, Italian, and Spanish to the best of the local model and app rules. Receipt scanning is currently English-only.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appThemeMode) {
                Text("System Default").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 10) {
                Text("App Icon")
                    .font(.subheadline)

                HStack(spacing: 12) {
                    ForEach(AppIconVariant.allCases) { variant in
                        Button {
                            setAppIcon(variant)
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColors.tertiaryBg)
                                    .frame(width: 54, height: 54)
                                    .overlay {
                                        Image(variant.previewAssetName)
                                            .resizable()
                                            .scaledToFill()
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                selectedAppIcon == variant
                                                    ? AppColors.accent
                                                    : AppColors.border,
                                                lineWidth: selectedAppIcon == variant ? 2 : 1
                                            )
                                    )

                                Text(variant.label)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(
                                        selectedAppIcon == variant
                                            ? AppColors.textPrimary
                                            : AppColors.textTertiary
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Appearance")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label("Delete All Expenses", systemImage: "trash")
                    .font(.subheadline)
            }
        } footer: {
            Text("This action cannot be undone.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("AI Model", value: "Qwen 2.5 0.5B")
            LabeledContent("Processing", value: "100% On-Device")
            LabeledContent("AI Use", value: "Expense Parsing Only")
            LabeledContent("Receipt OCR", value: "English Only")

            Button {
                openURL(Self.privacyPolicyURL)
            } label: {
                Text("Privacy Policy")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.blue)

            Text("View Onboarding Again")
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    showOnboardingReplay = true
                }
                .accessibilityAddTraits(.isButton)
        } header: {
            Text("About")
        } footer: {
            Text("PULDAR is not financial advice. Its on-device AI is only used to parse receipts and plain-English expense entries, then categorize them. It does not provide investment tips, debt strategies, or financial recommendations.")
        }
    }

    private func percentageBinding(for bucket: BudgetBucket) -> Binding<Double> {
        Binding(
            get: { draftPercentage(for: bucket) },
            set: { draftPercentages[bucket.rawValue] = min(max($0, 0), 1) }
        )
    }

    private func dismissActiveKeyboard() {
        if focusedIncomeField != nil {
            focusedIncomeField = nil
        }
    }

    private func draftPercentage(for bucket: BudgetBucket) -> Double {
        min(max(draftPercentages[bucket.rawValue] ?? budgetEngine.percentage(for: bucket), 0), 1)
    }

    private func draftBucketBudget(for bucket: BudgetBucket) -> Double {
        budgetEngine.monthlyIncome * draftPercentage(for: bucket)
    }

    private func draftBucketBudgetDisplay(for bucket: BudgetBucket) -> String {
        guard budgetEngine.monthlyIncome > 0 else { return "$ --" }
        return draftBucketBudget(for: bucket).formattedCurrency(code: appPreferences.currencyCode)
    }

    private var incomeInputMode: IncomeInputMode {
        IncomeInputMode(rawValue: incomeInputModeRaw) ?? .monthly
    }

    private var incomeInputModeBinding: Binding<IncomeInputMode> {
        Binding(
            get: { incomeInputMode },
            set: { newValue in
                guard newValue.rawValue != incomeInputModeRaw else { return }
                incomeInputModeRaw = newValue.rawValue
                HapticManager.selection()
                if newValue == .hourly {
                    recalculateMonthlyIncomeFromHourlyInputs()
                }
            }
        )
    }

    private var estimatedMonthlyIncome: Double {
        let hourly = max(hourlyPayRate, 0)
        let hours = max(hoursPerWeek, 0)
        return (hourly * hours * 52) / 12
    }

    private func recalculateMonthlyIncomeFromHourlyInputs() {
        let parsedHourly = Double(hourlyPayText) ?? hourlyPayRate
        let parsedHours = Double(hoursPerWeekText) ?? hoursPerWeek
        let safeHourly = (parsedHourly.isFinite ? max(parsedHourly, 0) : 0)
        let safeHours = (parsedHours.isFinite ? max(parsedHours, 0) : 0)

        hourlyPayRate = safeHourly
        hoursPerWeek = safeHours
        budgetEngine.monthlyIncome = estimatedMonthlyIncome
        incomeText = String(format: "%.0f", budgetEngine.monthlyIncome)
    }

    private var totalDraftPercentage: Double {
        BudgetBucket.allCases.reduce(0) { $0 + draftPercentage(for: $1) }
    }

    private var isAllocationValid: Bool {
        Int(round(totalDraftPercentage * 100)) == 100
    }

    private func currentPercentagesSnapshot() -> [String: Double] {
        var values: [String: Double] = [:]
        for bucket in BudgetBucket.allCases {
            values[bucket.rawValue] = budgetEngine.percentage(for: bucket)
        }
        return values
    }

    private func recurringBucketLabel(_ bucket: BudgetBucket) -> String {
        switch bucket {
        case .fundamentals: return "Need"
        case .fun: return "Want"
        case .future: return "Invest"
        }
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide))
    }

    private func exportCurrentMonthCSV() {
        let calendar = Calendar.current
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) ?? .now
        let currentMonthExpenses = expenses.filter {
            calendar.isDate($0.date, equalTo: currentMonth, toGranularity: .month)
        }
        exportCSV(for: currentMonthExpenses, scope: monthLabel(currentMonth))
    }

    private func exportCSV(for items: [Expense], scope: String) {
        let rows = items.map { expense in
            ExpenseExportService.ExpenseRow(
                date: expense.date,
                merchant: expense.merchant,
                amount: expense.amount,
                categoryDisplay: categoryManager.displayName(forStoredCategory: expense.category),
                bucket: expense.bucket,
                isOverspent: expense.isOverspent,
                notes: expense.notes
            )
        }
        let rowCount = items.count

        Task.detached(priority: .userInitiated) {
            do {
                let url = try ExpenseExportService.writeCSV(rows: rows, scope: scope)
                await MainActor.run {
                    diagnosticLogger.record(
                        category: "export.csv",
                        message: "Exported CSV from settings",
                        metadata: ["scope": scope, "rows": "\(rowCount)"]
                    )
                    shareSheetURL = SharedFile(url: url)
                }
            } catch {
                await MainActor.run {
                    diagnosticLogger.record(
                        level: .error,
                        category: "export.csv",
                        message: "Failed CSV export from settings",
                        metadata: ["error": error.localizedDescription]
                    )
                }
            }
        }
    }

    private func recurringActiveBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                recurringExpenses.first(where: { $0.id == id })?.isActive ?? true
            },
            set: { isOn in
                guard let recurring = recurringExpenses.first(where: { $0.id == id }) else { return }
                recurring.isActive = isOn
                recurring.touchUpdatedAt()
                do {
                    try modelContext.save()
                    budgetEngine.markDataChanged()
                    diagnosticLogger.record(
                        category: "recurring.toggle",
                        message: "Updated recurring expense activity",
                        metadata: [
                            "name": recurring.name,
                            "isActive": isOn ? "true" : "false"
                        ]
                    )
                } catch {
                    print("Failed to update recurring active state: \(error)")
                    diagnosticLogger.record(
                        level: .error,
                        category: "recurring.toggle",
                        message: "Failed to update recurring expense activity",
                        metadata: ["error": error.localizedDescription]
                    )
                }
            }
        )
    }

    private var rolloverBinding: Binding<Bool> {
        Binding(
            get: { budgetEngine.rolloverEnabled },
            set: {
                budgetEngine.rolloverEnabled = $0
                HapticManager.selection()
            }
        )
    }

    private func adjustPercentage(for bucket: BudgetBucket, by delta: Double) {
        let current = draftPercentage(for: bucket)
        let snapped = (round((current + delta) * 100) / 100)
        let clamped = min(max(snapped, 0), 1)
        guard clamped != current else { return }
        draftPercentages[bucket.rawValue] = clamped
        HapticManager.selection()
    }

    private func applySelectedPresetIfNeeded() {
        guard let values = selectedAllocationPreset.values else { return }
        draftPercentages = values
    }

    private func saveAndDismiss() {
        budgetEngine.setPercentages(draftPercentages)
        diagnosticLogger.record(
            category: "budget.settings",
            message: "Saved settings changes",
            metadata: currentPercentagesSnapshot().mapValues { String(format: "%.2f", $0) }
        )
        if focusedIncomeField != nil {
            focusedIncomeField = nil
        }
    }

    private enum AllocationPreset: String, CaseIterable, Identifiable {
        case fiftyThirtyTwenty
        case sixtyTwentyTwenty
        case seventyTwentyTen
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fiftyThirtyTwenty: return "50/30/20"
            case .sixtyTwentyTwenty: return "60/20/20"
            case .seventyTwentyTen:  return "70/20/10"
            case .custom: return "Custom"
            }
        }

        var values: [String: Double]? {
            switch self {
            case .fiftyThirtyTwenty:
                return [
                    BudgetBucket.fundamentals.rawValue: 0.50,
                    BudgetBucket.fun.rawValue: 0.30,
                    BudgetBucket.future.rawValue: 0.20
                ]
            case .sixtyTwentyTwenty:
                return [
                    BudgetBucket.fundamentals.rawValue: 0.60,
                    BudgetBucket.fun.rawValue: 0.20,
                    BudgetBucket.future.rawValue: 0.20
                ]
            case .seventyTwentyTen:
                return [
                    BudgetBucket.fundamentals.rawValue: 0.70,
                    BudgetBucket.fun.rawValue: 0.20,
                    BudgetBucket.future.rawValue: 0.10
                ]
            case .custom:
                return nil
            }
        }

        static func matching(
            _ values: [String: Double],
            tolerance: Double = 0.0001
        ) -> AllocationPreset? {
            for preset in [AllocationPreset.fiftyThirtyTwenty, .sixtyTwentyTwenty, .seventyTwentyTen] {
                guard let presetValues = preset.values else { continue }
                let isMatch = BudgetBucket.allCases.allSatisfy { bucket in
                    abs((values[bucket.rawValue] ?? 0) - (presetValues[bucket.rawValue] ?? 0)) <= tolerance
                }
                if isMatch {
                    return preset
                }
            }
            return nil
        }
    }

    private func addRecurringExpense() {
        let trimmedName = newRecurringName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            addRecurringError = "Please enter a name."
            return
        }

        guard let amount = Double(newRecurringAmount), amount.isFinite, amount > 0 else {
            addRecurringError = "Please enter a valid monthly amount."
            return
        }

        let recurring = RecurringExpense(
            name: trimmedName.normalizedMerchantName(),
            amount: amount,
            bucket: newRecurringBucket
        )

        modelContext.insert(recurring)
        do {
            try modelContext.save()
            budgetEngine.markDataChanged()
            HapticManager.success()
            showAddRecurringSheet = false
            diagnosticLogger.record(
                category: "recurring.create",
                message: "Created recurring expense",
                metadata: [
                    "name": trimmedName,
                    "amount": String(format: "%.2f", amount),
                    "budget": newRecurringBucket.rawValue
                ]
            )
        } catch {
            addRecurringError = "Could not save recurring expense."
            print("Failed to save recurring expense: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "recurring.create",
                message: "Failed to create recurring expense",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func deleteRecurringExpenses(at offsets: IndexSet) {
        for index in offsets {
            guard recurringExpenses.indices.contains(index) else { continue }
            modelContext.delete(recurringExpenses[index])
        }

        do {
            try modelContext.save()
            budgetEngine.markDataChanged()
            HapticManager.warning()
            diagnosticLogger.record(
                category: "recurring.delete",
                message: "Deleted recurring expenses",
                metadata: ["count": "\(offsets.count)"]
            )
        } catch {
            print("Failed to delete recurring expenses: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "recurring.delete",
                message: "Failed to delete recurring expenses",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    // MARK: - Data Operations

    private func clearAllExpenses() {
        do {
            try modelContext.delete(model: Expense.self)
            try modelContext.delete(model: RecurringExpense.self)
            budgetEngine.markDataChanged()
            HapticManager.warning()
            diagnosticLogger.record(
                category: "danger.clear_all",
                message: "Cleared all expenses and recurring expenses"
            )
        } catch {
            print("Failed to delete expenses: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "danger.clear_all",
                message: "Failed to clear all expenses",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    // MARK: - App Icon

    private func setAppIcon(_ variant: AppIconVariant) {
        guard variant != selectedAppIcon else { return }
        selectedAppIcon = variant
        HapticManager.selection()
        UIApplication.shared.setAlternateIconName(variant.iconName) { error in
            if let error {
                print("Failed to set app icon: \(error)")
            }
        }
    }
}

private struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - App Icon Variant

enum AppIconVariant: String, CaseIterable, Identifiable {
    case colorOnWhite
    case colorOnBlack
    case blackOnWhite
    case tinted

    var id: String { rawValue }

    /// Returns `nil` for the ship icon (`colorOnWhite`), since the main
    /// AppIcon.appiconset already carries the color-on-white artwork.
    var iconName: String? {
        switch self {
        case .colorOnWhite: return nil
        case .colorOnBlack: return "AppIconColorOnBlack"
        case .blackOnWhite: return "AppIconBlackOnWhite"
        case .tinted: return "AppIconTinted"
        }
    }

    var label: String {
        switch self {
        case .colorOnWhite: return "Color"
        case .colorOnBlack: return "Color Dark"
        case .blackOnWhite: return "Classic"
        case .tinted: return "Tinted"
        }
    }

    var previewAssetName: String {
        switch self {
        case .colorOnWhite: return "AppIconColorOnWhitePreview"
        case .colorOnBlack: return "AppIconColorOnBlackPreview"
        case .blackOnWhite: return "AppIconBlackOnWhitePreview"
        case .tinted: return "AppIconTintedPreview"
        }
    }

    static var current: AppIconVariant {
        guard let name = UIApplication.shared.alternateIconName else {
            return .colorOnWhite
        }
        return allCases.first { $0.iconName == name } ?? .colorOnWhite
    }
}
