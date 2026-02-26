import SwiftUI
import SwiftData

/// Settings sheet — income, allocation, and category management.
struct SettingsView: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(StoreKitManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringExpense.createdAt, order: .reverse)
    private var recurringExpenses: [RecurringExpense]

    @State private var incomeText: String = ""
    @FocusState private var isIncomeFocused: Bool
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

    var body: some View {
        NavigationStack {
            Form {
                // ── Income Section ─────────────────────────────────────
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(AppColors.textTertiary)
                        TextField("Monthly income", text: $incomeText)
                            .keyboardType(.decimalPad)
                            .focused($isIncomeFocused)
                            .onChange(of: incomeText) {
                                if let value = Double(incomeText) {
                                    budgetEngine.monthlyIncome = value
                                }
                            }
                    }
                } header: {
                    Text("Monthly Income")
                } footer: {
                    Text("Your income is stored locally and never leaves this device.")
                }

                // ── Bucket Allocation ──────────────────────────────────
                Section {
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
                                    if budgetEngine.monthlyIncome > 0 {
                                        Text(
                                            draftBucketBudget(for: bucket),
                                            format: .currency(code: "USD")
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textTertiary)
                                    }
                                }
                            }

                            Slider(
                                value: percentageBinding(for: bucket),
                                in: 0...1,
                                step: 0.01
                            )
                        }
                    }
                } header: {
                    Text("Bucket Allocation")
                } footer: {
                    Text(
                        "Total: \(Int(totalDraftPercentage * 100))%. " +
                        (isAllocationValid
                            ? "Tap Done to save."
                            : "Must equal exactly 100% to save.")
                    )
                    .foregroundStyle(isAllocationValid ? AppColors.textTertiary : AppColors.overspend)
                }

                // ── Recurring Expenses ─────────────────────────────────
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recurring expenses are a Pro feature.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                            Button {
                                showPaywall = true
                            } label: {
                                Label("Unlock Pro (\(AppConstants.proPrice))", systemImage: "lock.open")
                            }
                        }
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

                // ── Custom Categories ──────────────────────────────────
                Section {
                    if categoryManager.customCategories.isEmpty {
                        Text("No custom categories yet.")
                            .foregroundStyle(AppColors.textTertiary)
                    } else {
                        ForEach(categoryManager.customCategories) { custom in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(
                                    "Category name",
                                    text: customNameBinding(for: custom.id)
                                )
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

                // ── Pro Status ─────────────────────────────────────────
                Section("Account") {
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
                }

                // ── Danger Zone ────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        clearAllExpenses()
                    } label: {
                        Label("Delete All Expenses", systemImage: "trash")
                            .font(.subheadline)
                    }
                } footer: {
                    Text("This action cannot be undone.")
                }

                // ── About ──────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("AI Model", value: "Qwen 2.5 0.5B")
                    LabeledContent("Processing", value: "100% On-Device")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        budgetEngine.setPercentages(draftPercentages)
                        dismiss()
                    }
                        .fontWeight(.medium)
                        .disabled(!isAllocationValid)
                }
            }
            .onAppear {
                if budgetEngine.monthlyIncome > 0 {
                    incomeText = String(format: "%.0f", budgetEngine.monthlyIncome)
                }
                draftPercentages = currentPercentagesSnapshot()
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
                    .navigationTitle("Recurring Expense")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAddRecurringSheet = false }
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
                    .navigationTitle("New Category")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAddCategorySheet = false }
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
        }
    }

    // MARK: - Helpers

    private func percentageBinding(for bucket: BudgetBucket) -> Binding<Double> {
        Binding(
            get: { draftPercentage(for: bucket) },
            set: { draftPercentages[bucket.rawValue] = min(max($0, 0), 1) }
        )
    }

    private func draftPercentage(for bucket: BudgetBucket) -> Double {
        min(max(draftPercentages[bucket.rawValue] ?? budgetEngine.percentage(for: bucket), 0), 1)
    }

    private func draftBucketBudget(for bucket: BudgetBucket) -> Double {
        budgetEngine.monthlyIncome * draftPercentage(for: bucket)
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
            HapticManager.warning()
        } catch {
            print("Failed to delete expenses: \(error)")
        }
    }
}
