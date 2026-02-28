import SwiftUI
import SwiftData
import UIKit

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
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(StoreKitManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
    @State private var showPaywall = false
    @State private var exportURL: URL?
    @State private var backupURL: URL?
    @State private var selectedAllocationPreset: AllocationPreset = .custom
    @State private var showZeroFunWarning = false
    @State private var showDeleteAllConfirmation = false
    @State private var deleteConfirmText = ""
    @AppStorage("appThemeMode") private var appThemeMode = "system"
    @AppStorage("incomeInputMode") private var incomeInputModeRaw = IncomeInputMode.monthly.rawValue
    @AppStorage("hourlyPayRate") private var hourlyPayRate: Double = 0
    @AppStorage("hoursPerWeek") private var hoursPerWeek: Double = 40
    @AppStorage("autoMonthlyCSVExportEnabled") private var autoMonthlyCSVExportEnabled = false
    @AppStorage("lastAutoMonthlyCSVExportKey") private var lastAutoMonthlyCSVExportKey = ""

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
                proSection
                recurringSection
                rolloverSection
                dataExportSection
                localBackupSection
                appearanceSection
                customCategoriesSection
                accountSection
                dangerZoneSection
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissActiveKeyboard()
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
                if !store.isPro, budgetEngine.rolloverEnabled {
                    budgetEngine.rolloverEnabled = false
                }
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
            .onChange(of: store.isPro) {
                if !store.isPro, budgetEngine.rolloverEnabled {
                    budgetEngine.rolloverEnabled = false
                }
            }
            .onChange(of: draftPercentages) {
                selectedAllocationPreset = AllocationPreset.matching(draftPercentages) ?? .custom
            }
            .onChange(of: autoMonthlyCSVExportEnabled) {
                runAutoMonthlyExportIfNeeded()
            }
            .task {
                await store.loadProducts()
                await store.checkEntitlement()
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showDeleteAllConfirmation) {
                deleteConfirmationSheet
            }
            .alert("Fun is 0%", isPresented: $showZeroFunWarning) {
                Button("Keep 0%") {
                    saveAndDismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Fun is set to 0%. Are you sure you want to continue?")
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
                    Text(estimatedMonthlyIncome, format: .currency(code: "USD"))
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
                            Text(bucket.rawValue)
                                .font(.subheadline.weight(.medium))
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
            Text("Bucket Allocation")
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
            if store.isPro {
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

                            Text(recurring.safeAmount, format: .currency(code: "USD"))
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
            } else {
                Text("Recurring expenses are available on Pro.")
                    .foregroundStyle(AppColors.textTertiary)
            }
        } header: {
            Text("Recurring Expenses")
        } footer: {
            Text(
                store.isPro
                ? "These are auto-accounted for every month."
                : "Upgrade to Pro for recurring transactions and unlimited entries."
            )
        }
    }

    @ViewBuilder
    private var proSection: some View {
        if !store.isPro {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Unlock Premium Features")
                        .font(.subheadline.weight(.semibold))
                    Text("Unlimited entries, recurring expenses, rollover budgets, and CSV exports.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Upgrade for \(AppConstants.proPrice)", systemImage: "sparkles")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Puldar Pro")
            }
        }
    }

    private var rolloverSection: some View {
        Section {
            if store.isPro {
                Toggle("Enable Rollover Balances", isOn: rolloverBinding)
                    .tint(AppColors.accent)
                Text("Unused Fundamentals and Fun money rolls into next month.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                Text("Rollover balances are available on Pro.")
                    .foregroundStyle(AppColors.textTertiary)
            }
        } header: {
            Text("Rollover Budgets")
        }
    }

    private var dataExportSection: some View {
        Section {
            if store.isPro {
                Button("Export Current Month (CSV)") {
                    exportCurrentMonthCSV()
                }
                Button("Export All Data (CSV)") {
                    exportCSV(for: expenses, scope: "all_months")
                }
                Toggle("Auto Monthly CSV Export", isOn: $autoMonthlyCSVExportEnabled)
                    .tint(AppColors.accent)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share Last Export", systemImage: "square.and.arrow.up")
                    }
                }
            } else {
                Text("Exports are available on Pro.")
                    .foregroundStyle(AppColors.textTertiary)
                lockedExportPreview
            }
        } header: {
            Text("Data Export")
        }
    }

    private var localBackupSection: some View {
        Section {
            Button("Create Device Backup (JSON)") {
                exportLocalBackupJSON()
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

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appThemeMode) {
                Text("System Default").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Appearance")
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Text("Plan")
                Spacer()
                Text(store.isPro ? "Pro (Lifetime)" : "Free")
                    .foregroundStyle(
                        store.isPro ? .green : AppColors.textSecondary
                    )
            }

            if !store.isPro {
                Button("Restore Purchases") {
                    Task { await store.checkEntitlement(force: true) }
                }
            }
        } header: {
            Text("Account")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                deleteConfirmText = ""
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
        } header: {
            Text("About")
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
        focusedIncomeField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func draftPercentage(for bucket: BudgetBucket) -> Double {
        min(max(draftPercentages[bucket.rawValue] ?? budgetEngine.percentage(for: bucket), 0), 1)
    }

    private func draftBucketBudget(for bucket: BudgetBucket) -> Double {
        budgetEngine.monthlyIncome * draftPercentage(for: bucket)
    }

    private func draftBucketBudgetDisplay(for bucket: BudgetBucket) -> String {
        guard budgetEngine.monthlyIncome > 0 else { return "$ --" }
        return draftBucketBudget(for: bucket).formatted(.currency(code: "USD"))
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
        } catch {
            print("Failed to export CSV in settings: \(error)")
        }
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func runAutoMonthlyExportIfNeeded() {
        guard store.isPro, autoMonthlyCSVExportEnabled else { return }

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

    private func recurringActiveBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                recurringExpenses.first(where: { $0.id == id })?.isActive ?? true
            },
            set: { isOn in
                guard store.isPro else {
                    showPaywall = true
                    return
                }
                guard let recurring = recurringExpenses.first(where: { $0.id == id }) else { return }
                recurring.isActive = isOn
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to update recurring active state: \(error)")
                }
            }
        )
    }

    private var rolloverBinding: Binding<Bool> {
        Binding(
            get: { budgetEngine.rolloverEnabled },
            set: { isOn in
                guard store.isPro else {
                    showPaywall = true
                    return
                }
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
        dismiss()
    }

    private var lockedExportPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("date,merchant,amount,category,bucket")
                Text("2026-02-27,Whole Foods,45.00,Groceries,Fundamentals")
                Text("2026-02-26,Bitcoin,200.00,Investments,Future You")
                Text("2026-02-25,Hulu,9.99,Subscriptions,Fun")
            }
            .font(.caption2.monospaced())
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.tertiaryBg)
            )
            .blur(radius: 2.4)
            .overlay(alignment: .center) {
                Label("Pro Export Preview", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.background.opacity(0.92))
                    )
            }
        }
    }

    private var deleteConfirmationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Type DELETE to permanently remove all expenses.")
                        .font(.subheadline)
                    TextField("DELETE", text: $deleteConfirmText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                }

                Section {
                    Button(role: .destructive) {
                        guard deleteConfirmText == "DELETE" else { return }
                        clearAllExpenses()
                        showDeleteAllConfirmation = false
                    } label: {
                        Text("Delete Everything")
                    }
                    .disabled(deleteConfirmText != "DELETE")
                }
            }
            .navigationTitle("Confirm Deletion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDeleteAllConfirmation = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
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
        guard store.isPro else {
            showPaywall = true
            return
        }

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
            showAddRecurringSheet = false
        } catch {
            addRecurringError = "Could not save recurring expense."
            print("Failed to save recurring expense: \(error)")
        }
    }

    private func deleteRecurringExpenses(at offsets: IndexSet) {
        guard store.isPro else {
            showPaywall = true
            return
        }

        for index in offsets {
            guard recurringExpenses.indices.contains(index) else { continue }
            modelContext.delete(recurringExpenses[index])
        }

        do {
            try modelContext.save()
            HapticManager.warning()
        } catch {
            print("Failed to delete recurring expenses: \(error)")
        }
    }

    // MARK: - Data Operations

    private func clearAllExpenses() {
        do {
            try modelContext.delete(model: Expense.self)
            try modelContext.delete(model: RecurringExpense.self)
            HapticManager.warning()
        } catch {
            print("Failed to delete expenses: \(error)")
        }
    }

    private func exportLocalBackupJSON() {
        let payload = LocalBackupPayload(
            createdAt: .now,
            monthlyIncome: budgetEngine.monthlyIncome,
            percentages: currentPercentagesSnapshot(),
            expenses: expenses.map {
                LocalBackupExpense(
                    id: $0.id,
                    date: $0.date,
                    merchant: $0.merchant,
                    amount: $0.amount,
                    category: $0.category,
                    bucket: $0.bucket,
                    isOverspent: $0.isOverspent,
                    notes: $0.notes
                )
            },
            recurring: recurringExpenses.map {
                LocalBackupRecurring(
                    id: $0.id,
                    name: $0.name,
                    amount: $0.amount,
                    bucket: $0.bucket,
                    isActive: $0.isActive,
                    createdAt: $0.createdAt
                )
            }
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
        } catch {
            print("Failed to create local backup: \(error)")
        }
    }

    private struct LocalBackupPayload: Codable {
        let createdAt: Date
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
