import SwiftUI
import SwiftData

/// Settings sheet — income, allocation, and category management.
struct SettingsView: View {
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
    @Environment(FinanceKitManager.self) private var financeKitManager
    @Environment(\.dismiss) private var dismiss
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
    @State private var showAddCategorySheet = false
    @State private var newCategoryName = ""
    @State private var newCategoryBucket: BudgetBucket = .fun
    @State private var addCategoryError: String?
    @State private var draftPercentages: [String: Double] = [:]
    @State private var showAddRecurringSheet = false
    @State private var newRecurringName = ""
    @State private var newRecurringAmount = ""
    @State private var newRecurringBucket: BudgetBucket = .fun
    @State private var addRecurringError: String?
    @State private var exportURL: URL?
    @State private var backupURL: URL?
    @State private var diagnosticURL: URL?
    @State private var selectedAllocationPreset: AllocationPreset = .custom
    @State private var showZeroFunWarning = false
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteAllAlert = false
    @State private var showBudgetAllocationInfo = false
    @State private var selectedBudgetInfoBucket: BudgetBucket?
    @State private var financeKitNotice: FinanceKitManager.Notice?
    @AppStorage("appThemeMode") private var appThemeMode = "system"
    @State private var selectedAppIcon: AppIcon = AppIconManager.current
    @AppStorage("didCompleteAppOnboarding") private var didCompleteAppOnboarding = false
    @AppStorage("incomeInputMode") private var incomeInputModeRaw = IncomeInputMode.monthly.rawValue
    @AppStorage("hourlyPayRate") private var hourlyPayRate: Double = 0
    @AppStorage("hoursPerWeek") private var hoursPerWeek: Double = 40
    @AppStorage("autoMonthlyCSVExportEnabled") private var autoMonthlyCSVExportEnabled = false
    @AppStorage("lastAutoMonthlyCSVExportKey") private var lastAutoMonthlyCSVExportKey = ""

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
                localBackupSection
                languageAndCurrencySection
                appearanceSection
                widgetsSection
                appleWalletSyncSection
                customCategoriesSection
                accountSection
                diagnosticsSection
                dangerZoneSection
                aboutSection
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if focusedIncomeField != nil {
                        dismissActiveKeyboard()
                    }
                }
            )
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if draftPercentage(for: .fun) <= 0.0001 {
                            showZeroFunWarning = true
                        } else {
                            dismissActiveKeyboard()
                            saveAndDismiss()
                        }
                    }
                        .fontWeight(.medium)
                        .disabled(!isAllocationValid)
                }
            }
            .onAppear {
                financeKitManager.refreshAvailability()
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
                runAutoMonthlyExportIfNeeded()
            }
            .onChange(of: draftPercentages) {
                selectedAllocationPreset = AllocationPreset.matching(draftPercentages) ?? .custom
            }
            .onChange(of: autoMonthlyCSVExportEnabled) {
                runAutoMonthlyExportIfNeeded()
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
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            dismissActiveKeyboard()
                        }
                    )
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
            .sheet(isPresented: $showAddCategorySheet) {
                NavigationStack {
                    Form {
                        TextField("Category name", text: $newCategoryName)
                            .textInputAutocapitalization(.words)

                        Picker("Bucket", selection: $newCategoryBucket) {
                            ForEach(BudgetBucket.allCases) { bucket in
                                Text(bucket.rawValue).tag(bucket)
                            }
                        }

                        if let addCategoryError {
                            Text(addCategoryError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            dismissActiveKeyboard()
                        }
                    )
                    .navigationTitle("New Category")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                dismissActiveKeyboard()
                                showAddCategorySheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { addCustomCategory() }
                        }
                    }
                }
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
            .alert(item: $financeKitNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
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
            }

            ForEach(BudgetBucket.allCases) { bucket in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: bucket.icon)
                            .font(.system(size: 12, weight: .thin))
                            .foregroundStyle(bucket.color)
                            .frame(width: 20)

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

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(draftPercentage(for: bucket) * 100))%")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    HStack(spacing: 10) {
                        Slider(
                            value: percentageBinding(for: bucket),
                            in: 0...1,
                            step: 0.01
                        )
                        Text(draftBucketBudgetDisplay(for: bucket))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                            .frame(minWidth: 92, alignment: .trailing)
                    }
                }
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
                    Text("Enter income above to calculate dollar targets.")
                        .foregroundStyle(AppColors.textTertiary)
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
            Text("These are auto-accounted for every month.")
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

    private var appleWalletSyncSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Status", value: financeKitManager.statusTitle)

                Text(financeKitManager.detailText)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                if let lastSyncError = financeKitManager.lastSyncError {
                    Text(lastSyncError)
                        .font(.caption)
                        .foregroundStyle(AppColors.overspend)
                }

                if financeKitManager.lastImportedCount > 0 {
                    Text("Last Apple Wallet import added \(financeKitManager.lastImportedCount) transaction(s).")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Button(financeKitManager.primaryActionTitle) {
                    financeKitManager.refreshAvailability()
                    financeKitNotice = financeKitManager.primaryActionNotice()
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Apple Wallet Sync")
        } footer: {
            Text("When available, this will import Apple Card, Apple Cash, and Savings activity without using third-party aggregators. If it is unavailable, PULDAR falls back to manual entry, receipt scanning, and CSV/JSON portability.")
        }
    }

    private var rolloverSection: some View {
        Section {
            Toggle("Enable Rollover Balances", isOn: rolloverBinding)
                .tint(AppColors.accent)
            Text("Unused Fundamentals and Fun money rolls into next month.")
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)
        } header: {
            Text("Rollover Budgets")
        }
    }

    private var dataExportSection: some View {
        Section {
            Button("Export Current Month Entries (CSV)") {
                exportCurrentMonthCSV()
            }
            Button("Export Current Month Snapshot (JSON)") {
                exportCurrentMonthJSON()
            }
            Button("Export All Entries (CSV)") {
                exportCSV(for: expenses, scope: "all_entries")
            }
            Button("Export All Data (JSON)") {
                exportJSON(
                    expenses: expenses,
                    recurring: recurringExpenses,
                    scope: "all_data"
                )
            }
            Toggle("Auto Monthly CSV Export", isOn: $autoMonthlyCSVExportEnabled)
                .tint(AppColors.accent)
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share Last Export", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Data Export")
        }
    }

    private var localBackupSection: some View {
        Section {
            Button("Create Full Device Backup (JSON)") {
                exportFullBackupJSON()
            }
            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Share Last Backup", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Local Backup")
        } footer: {
            Text("Creates a raw on-device backup file you can transfer to another phone.")
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

            VStack(alignment: .leading, spacing: 12) {
                Text("App Icon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(AppIcon.allCases) { icon in
                            Button {
                                selectedAppIcon = icon
                                AppIconManager.apply(icon)
                                HapticManager.selection()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(icon.previewImageName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(
                                                    selectedAppIcon == icon ? Color.accentColor : Color.clear,
                                                    lineWidth: 2.5
                                                )
                                        )
                                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                                    Text(icon.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(selectedAppIcon == icon ? .primary : .secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Appearance")
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Text("Access")
                Spacer()
                Text("All features included")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("This version of PULDAR includes recurring expenses, rollover budgets, exports, and unlimited entries for everyone.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Toggle(
                "Enable Local Diagnostic Logs",
                isOn: Binding(
                    get: { diagnosticLogger.isEnabled },
                    set: { diagnosticLogger.setEnabled($0) }
                )
            )
            .tint(AppColors.accent)

            Button("Export Diagnostic Logs") {
                exportDiagnosticLogs()
            }
            .disabled(!diagnosticLogger.isEnabled && diagnosticLogger.entries.isEmpty)

            if let diagnosticURL {
                ShareLink(item: diagnosticURL) {
                    Label("Share Diagnostic File", systemImage: "envelope")
                }
            }

            if !diagnosticLogger.entries.isEmpty {
                Button("Clear Local Diagnostic Logs", role: .destructive) {
                    diagnosticLogger.clear()
                    diagnosticURL = nil
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Optional. Logs stay on this device and only include app events like budget changes, exports, and errors. Nothing is sent anywhere unless the user exports and shares the file.")
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

            Button("View Onboarding Again") {
                dismiss()
                DispatchQueue.main.async {
                    didCompleteAppOnboarding = false
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("PULDAR is not financial advice. Its on-device AI is only used to parse receipts and plain-English expense entries, then categorize them. It does not provide investment tips, debt strategies, or financial recommendations.")
        }
    }

    private var customCategoriesSection: some View {
        Section {
            if categoryManager.customCategories.isEmpty {
                Text("No custom categories yet.")
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(categoryManager.customCategories) { custom in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Category name", text: customNameBinding(for: custom.id))
                        Picker("Bucket", selection: customBucketBinding(for: custom.id)) {
                            ForEach(BudgetBucket.allCases) { bucket in
                                Text(bucket.rawValue).tag(bucket)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: categoryManager.removeCustomCategories)
            }

            Button {
                newCategoryName = ""
                newCategoryBucket = .fun
                addCategoryError = nil
                showAddCategorySheet = true
            } label: {
                Label("Add Category", systemImage: "plus")
            }
        } header: {
            Text("Custom Categories")
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
                incomeInputModeRaw = newValue.rawValue
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

    private func customNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                categoryManager.customCategories.first(where: { $0.id == id })?.name ?? ""
            },
            set: { newName in
                categoryManager.updateCustomCategory(id: id, name: newName)
            }
        )
    }

    private func customBucketBinding(for id: UUID) -> Binding<BudgetBucket> {
        Binding(
            get: {
                categoryManager.customCategories.first(where: { $0.id == id })?.bucket ?? .fun
            },
            set: { newBucket in
                categoryManager.updateCustomCategory(id: id, bucket: newBucket)
            }
        )
    }

    private func addCustomCategory() {
        let ok = categoryManager.addCustomCategory(
            name: newCategoryName,
            bucket: newCategoryBucket
        )

        guard ok else {
            addCategoryError = "This category already exists or is invalid."
            return
        }

        showAddCategorySheet = false
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

    private func exportCurrentMonthJSON() {
        let calendar = Calendar.current
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) ?? .now
        let currentMonthExpenses = expenses.filter {
            calendar.isDate($0.date, equalTo: currentMonth, toGranularity: .month)
        }
        exportJSON(
            expenses: currentMonthExpenses,
            recurring: recurringExpensesApplicable(to: currentMonth),
            scope: monthLabel(currentMonth)
        )
    }

    private func exportCSV(for items: [Expense], scope: String) {
        let formatter = ISO8601DateFormatter()
        var csv = "date,merchant,amount,category,bucket,isOverspent,notes\n"

        for expense in items.sorted(by: { $0.date > $1.date }) {
            let row = [
                csvEscape(formatter.string(from: expense.date)),
                csvEscape(expense.merchant),
                csvEscape(String(format: "%.2f", expense.amount)),
                csvEscape(categoryManager.displayName(forStoredCategory: expense.category)),
                csvEscape(expense.bucket),
                csvEscape(expense.isOverspent ? "true" : "false"),
                csvEscape(expense.notes)
            ].joined(separator: ",")
            csv += row + "\n"
        }

        let safeScope = scope.replacingOccurrences(
            of: "[^a-zA-Z0-9_]+",
            with: "_",
            options: .regularExpression
        )
        let filename = "puldar_\(safeScope.lowercased()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            diagnosticLogger.record(
                category: "export.csv",
                message: "Exported CSV from settings",
                metadata: ["scope": scope, "rows": "\(items.count)"]
            )
        } catch {
            print("Failed to export CSV in settings: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "export.csv",
                message: "Failed CSV export from settings",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func exportJSON(
        expenses: [Expense],
        recurring: [RecurringExpense],
        scope: String
    ) {
        let payload = DataExportPayload(
            createdAt: .now,
            scope: scope,
            monthlyIncome: budgetEngine.monthlyIncome,
            percentages: currentPercentagesSnapshot(),
            expenses: expenses.map(Self.makeLocalBackupExpense),
            recurring: recurring.map(Self.makeLocalBackupRecurring)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let safeScope = scope.replacingOccurrences(
            of: "[^a-zA-Z0-9_]+",
            with: "_",
            options: .regularExpression
        )
        let filename = "puldar_\(safeScope.lowercased()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
            exportURL = url
            diagnosticLogger.record(
                category: "export.json",
                message: "Exported JSON from settings",
                metadata: [
                    "scope": scope,
                    "expenses": "\(expenses.count)",
                    "recurring": "\(recurring.count)"
                ]
            )
        } catch {
            print("Failed to export JSON in settings: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "export.json",
                message: "Failed JSON export from settings",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func exportDiagnosticLogs() {
        let calendar = Calendar.current
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) ?? .now

        let state = DiagnosticLogger.SupportState(
            monthlyIncome: budgetEngine.monthlyIncome,
            rolloverEnabled: budgetEngine.rolloverEnabled,
            percentages: currentPercentagesSnapshot(),
            expenseCount: expenses.count,
            recurringExpenseCount: recurringExpenses.count,
            filteredMonth: monthLabel(currentMonth),
            monthSpent: budgetEngine.totalSpent(
                expenses: expenses,
                recurringExpenses: recurringExpenses,
                for: currentMonth
            ),
            monthCapacity: budgetEngine.monthSpendCapacity(
                expenses: expenses,
                recurringExpenses: recurringExpenses,
                for: currentMonth
            ),
            buckets: budgetEngine.calculateStatus(
                expenses: expenses,
                recurringExpenses: recurringExpenses,
                for: currentMonth
            ).map {
                DiagnosticLogger.SupportState.BucketState(
                    name: $0.bucket.rawValue,
                    budgeted: $0.budgeted,
                    spent: $0.spent,
                    remaining: $0.remaining,
                    isOverspent: $0.isOverspent
                )
            }
        )

        do {
            diagnosticURL = try diagnosticLogger.export(state: state)
            diagnosticLogger.record(
                category: "diagnostics.export",
                message: "Exported diagnostic log bundle",
                metadata: ["entries": "\(diagnosticLogger.entries.count)"]
            )
        } catch {
            diagnosticLogger.record(
                level: .error,
                category: "diagnostics.export",
                message: "Failed to export diagnostic log bundle",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func runAutoMonthlyExportIfNeeded() {
        guard autoMonthlyCSVExportEnabled else { return }

        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: .now) else {
            return
        }

        let key = monthKey(previousMonth)
        guard key != lastAutoMonthlyCSVExportKey else { return }

        let previousMonthExpenses = expenses.filter {
            calendar.isDate($0.date, equalTo: previousMonth, toGranularity: .month)
        }

        guard !previousMonthExpenses.isEmpty else {
            lastAutoMonthlyCSVExportKey = key
            return
        }

        exportCSV(for: previousMonthExpenses, scope: "auto_\(monthLabel(previousMonth))")
        lastAutoMonthlyCSVExportKey = key
    }

    private func monthKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private func recurringExpensesApplicable(to month: Date) -> [RecurringExpense] {
        let calendar = Calendar.current
        let targetMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        ) ?? month

        return recurringExpenses.filter { recurring in
            let recurringMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: recurring.createdAt)
            ) ?? recurring.createdAt
            return recurringMonth <= targetMonth
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
            set: { isOn in
                budgetEngine.rolloverEnabled = isOn
            }
        )
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
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    private enum AllocationPreset: String, CaseIterable, Identifiable {
        case fiftyThirtyTwenty
        case sixtyTwentyTwenty
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fiftyThirtyTwenty: return "50/30/20"
            case .sixtyTwentyTwenty: return "60/20/20"
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
            case .custom:
                return nil
            }
        }

        static func matching(
            _ values: [String: Double],
            tolerance: Double = 0.0001
        ) -> AllocationPreset? {
            for preset in [AllocationPreset.fiftyThirtyTwenty, .sixtyTwentyTwenty] {
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

    private func exportFullBackupJSON() {
        let payload = DataExportPayload(
            createdAt: .now,
            scope: "full_device_backup",
            monthlyIncome: budgetEngine.monthlyIncome,
            percentages: currentPercentagesSnapshot(),
            expenses: expenses.map(Self.makeLocalBackupExpense),
            recurring: recurringExpenses.map(Self.makeLocalBackupRecurring)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let filename = "puldar_backup_\(Int(Date.now.timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
            backupURL = url
            diagnosticLogger.record(
                category: "backup.json",
                message: "Created full device backup",
                metadata: [
                    "expenses": "\(expenses.count)",
                    "recurring": "\(recurringExpenses.count)"
                ]
            )
        } catch {
            print("Failed to create local backup: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "backup.json",
                message: "Failed to create full device backup",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    nonisolated private static func makeLocalBackupExpense(_ expense: Expense) -> LocalBackupExpense {
        LocalBackupExpense(
            id: expense.id,
            date: expense.date,
            merchant: expense.merchant,
            amount: expense.amount,
            category: expense.category,
            bucket: expense.bucket,
            isOverspent: expense.isOverspent,
            notes: expense.notes,
            source: expense.sourceKind.rawValue,
            externalTransactionID: expense.externalTransactionID,
            externalAccountID: expense.externalAccountID,
            importedAt: expense.importedAt
        )
    }

    nonisolated private static func makeLocalBackupRecurring(_ recurring: RecurringExpense) -> LocalBackupRecurring {
        LocalBackupRecurring(
            id: recurring.id,
            name: recurring.name,
            amount: recurring.amount,
            bucket: recurring.bucket,
            isActive: recurring.isActive,
            createdAt: recurring.createdAt
        )
    }

    private struct DataExportPayload: Codable {
        let createdAt: Date
        let scope: String
        let monthlyIncome: Double
        let percentages: [String: Double]
        let expenses: [LocalBackupExpense]
        let recurring: [LocalBackupRecurring]
    }

    private struct LocalBackupExpense: Codable {
        let id: UUID
        let date: Date
        let merchant: String
        let amount: Double
        let category: String
        let bucket: String
        let isOverspent: Bool
        let notes: String
        let source: String
        let externalTransactionID: String?
        let externalAccountID: String?
        let importedAt: Date?
    }

    private struct LocalBackupRecurring: Codable {
        let id: UUID
        let name: String
        let amount: Double
        let bucket: String
        let isActive: Bool
        let createdAt: Date
    }
}
