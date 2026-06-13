import SwiftUI
import SwiftData
import VisionKit

/// Isolated input dock subview so keystrokes in the composer don't invalidate
/// the entire `DashboardView` body.
private struct DashboardInputDock: View {
    let isProcessing: Bool
    let focusTrigger: Int
    let onSubmit: (String) async -> Bool
    let onCameraTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ExpenseInputView(
                isProcessing: isProcessing,
                onSubmit: onSubmit,
                focusTrigger: focusTrigger,
                onCameraTap: onCameraTap
            )
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            AppColors.secondaryBg
                .overlay(alignment: .top) {
                    AppColors.border.frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }
}

/// The main screen — orchestrates the entire expense-tracking flow.
///
/// Layout (top-to-bottom, Notion-style):
///   1. Donut chart  →  visual dashboard
///   2. Bucket bars   →  per-bucket progress
///   3. Text input    →  primary user intent
///   4. Search bar    →  filter & highlight
///   5. Expense list  →  progressive disclosure
struct DashboardView: View {
    @Binding var launchAction: DashboardLaunchAction?

    private struct RecurringSuggestion: Identifiable {
        let id = UUID()
        let name: String
        let amount: Double
        let bucket: BudgetBucket
    }

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(DiagnosticLogger.self) private var diagnosticLogger
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - SwiftData Query

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]
    @Query(sort: \RecurringExpense.createdAt, order: .reverse)
    private var recurringExpenses: [RecurringExpense]

    // MARK: - Local State

    @State private var isProcessing = false
    @State private var searchText = ""
    @State private var selectedBucketFilter: BudgetBucket?
    @State private var expandedBucket: BudgetBucket?
    @State private var recurringOpen = false
    @State private var txOpen = true
    @State private var showModelOnboarding = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var overspentBannerMessage: String?
    @State private var showOverspentBanner = false
    @State private var recurringSuggestion: RecurringSuggestion?
    @State private var showReceiptScanner = false
    @State private var composerFocusTrigger = 0
    @State private var editingExpense: Expense?
    @State private var editMerchant = ""
    @State private var editAmount = ""
    @State private var editCategory = ""
    @State private var editBucket: BudgetBucket = .fun
    @State private var editDate = Date.now
    @AppStorage("didCompleteAppOnboarding") private var didCompleteAppOnboarding = false
    @AppStorage("didCompleteModelOnboarding") private var didCompleteModelOnboarding = false
    @AppStorage("didRunCategoryConsistencyFixV2") private var didRunCategoryConsistencyFixV2 = false
    @AppStorage("didNormalizeMerchantsV1") private var didNormalizeMerchantsV1 = false
    @State private var didRunStartupMaintenance = false

    private var effectiveRecurringExpenses: [RecurringExpense] {
        recurringExpenses
    }

    private var bucketStatuses: [BudgetEngine.BucketStatus] {
        budgetEngine.calculateStatus(
            expenses: expenses,
            recurringExpenses: effectiveRecurringExpenses
        )
    }

    private var monthlyOverspentAmount: Double {
        budgetEngine.monthlyOverspentAmount(
            expenses: expenses,
            recurringExpenses: effectiveRecurringExpenses
        )
    }

    private var monthlySpendCapacity: Double {
        budgetEngine.monthSpendCapacity(
            expenses: expenses,
            recurringExpenses: effectiveRecurringExpenses
        )
    }

    private var monthlyUnderspentAmount: Double {
        return max(
            monthlySpendCapacity
                - budgetEngine.totalSpent(
                    expenses: expenses,
                    recurringExpenses: effectiveRecurringExpenses
                ),
            0
        )
    }

    private var recurringMonthlyTotal: Double {
        budgetEngine.recurringTotal(recurringExpenses)
    }

    private var dashboardMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 900 : .infinity
    }

    // MARK: - Body

    private var currentMonthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                dashboardContent
                    .frame(maxWidth: dashboardMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(AppColors.background)
            .refreshable {
                await refreshDashboard()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(currentMonthLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .toolbarBackground(AppColors.secondaryBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputDock
            }
            .fullScreenCover(isPresented: $showModelOnboarding) {
                ModelDownloadOnboardingView {
                    didCompleteModelOnboarding = true
                    showModelOnboarding = false
                }
                .environment(llmService)
                .environment(networkMonitor)
            }
            .sheet(isPresented: $showReceiptScanner) {
                ReceiptScannerView(currencyCode: appPreferences.currencyCode) { result in
                    showReceiptScanner = false

                    switch result {
                    case .success(let scannedText):
                        Task {
                            _ = await submitExpense(scannedText, source: .receiptScan)
                        }
                    case .failure(let error):
                        if error is CancellationError { return }
                        presentTransientError(error.localizedDescription)
                    }
                }
            }
            .sheet(item: $editingExpense) { _ in
                editExpenseSheet
            }
            .alert(
                "Make this recurring?",
                isPresented: Binding(
                    get: { recurringSuggestion != nil },
                    set: { if !$0 { recurringSuggestion = nil } }
                ),
                actions: {
                    Button("Not now", role: .cancel) {
                        recurringSuggestion = nil
                    }
                    Button("Add Recurring") {
                        addSuggestedRecurringExpense()
                    }
                },
                message: {
                    if let suggestion = recurringSuggestion {
                        Text(
                            "\(suggestion.name) appears monthly. Add \(suggestion.amount.formattedCurrency(code: appPreferences.currencyCode))/month to \(suggestion.bucket.rawValue)?"
                        )
                    }
                }
            )
            .task(id: didCompleteAppOnboarding) {
                await presentModelOnboardingIfNeeded()
            }
            .task {
                await scheduleStartupMaintenance()
            }
            .onAppear {
                consumeLaunchActionIfNeeded()
            }
            .onChange(of: launchAction?.id) {
                consumeLaunchActionIfNeeded()
            }
        }
    }

    private var totalSpentAmount: Double {
        budgetEngine.totalSpent(
            expenses: expenses,
            recurringExpenses: effectiveRecurringExpenses
        )
    }

    private var remainingAmount: Double {
        budgetEngine.monthlyIncome - totalSpentAmount
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 0) {
            modelStatusBanner

            if showError, let msg = errorMessage {
                errorBanner(msg)
            }
            if showOverspentBanner, let message = overspentBannerMessage {
                overspentEntryBanner(message)
            }

            // Hero number
            VStack(alignment: .leading, spacing: 0) {
                Text(heroFormattedAmount)
                    .font(.system(size: 56, weight: .ultraLight))
                    .kerning(-2)
                    .foregroundStyle(remainingAmount < 0 ? AppColors.overspend : AppColors.textPrimary)
                    .monospacedDigit()

                Text(remainingAmount < 0 ? "over budget" : "left this month")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Text("\(totalSpentAmount.formattedCurrency(code: appPreferences.currencyCode)) spent")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                        .monospacedDigit()

                    Circle()
                        .fill(AppColors.border)
                        .frame(width: 3, height: 3)

                    Text("\(budgetEngine.monthlyIncome.formattedCurrency(code: appPreferences.currencyCode)) income")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                        .monospacedDigit()
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 20)

            Divider()

            // Bucket rows with inline expand
            VStack(spacing: 0) {
                ForEach(bucketStatuses) { status in
                    BucketSummaryRow(
                        status: status,
                        isSelected: expandedBucket == status.bucket,
                        onTap: {
                            HapticManager.light()
                            withAnimation(.easeInOut(duration: 0.22)) {
                                expandedBucket = expandedBucket == status.bucket ? nil : status.bucket
                            }
                        },
                        items: expenses.filter { $0.budgetBucket == status.bucket },
                        recurringItems: effectiveRecurringExpenses.filter { $0.budgetBucket == status.bucket },
                        onEditExpense: { setEditingExp($0) }
                    )
                    Divider()
                }
            }

            // Collapsible Recurring
            if recurringMonthlyTotal > 0 {
                collapsibleRecurringSection
                Divider()
            }

            // Collapsible Transaction list
            collapsibleTransactionSection

            if budgetEngine.monthlyIncome == 0 {
                incomePrompt
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }

            Spacer(minLength: 140)
        }
    }

    private var heroFormattedAmount: String {
        let value = abs(remainingAmount)
        let formatted = value.formattedCurrency(code: appPreferences.currencyCode)
        return remainingAmount < 0 ? "-\(formatted)" : formatted
    }

    private func setEditingExp(_ expense: Expense) {
        editMerchant = expense.normalizedMerchant
        editAmount = String(format: "%.2f", expense.amount)
        editCategory = expense.category
        editBucket = expense.budgetBucket
        editDate = expense.date
        editingExpense = expense
    }

    private func saveInlineEdit() {
        guard let expense = editingExpense,
              let amount = Double(editAmount), amount > 0 else { return }
        expense.merchant = editMerchant
        expense.amount = amount
        expense.bucket = editBucket.rawValue
        expense.date = editDate
        try? modelContext.save()
        budgetEngine.markDataChanged()
        editingExpense = nil
    }

    private var editExpenseSheet: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(AppColors.border)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            // Header
            HStack {
                Button("Cancel") { editingExpense = nil }
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text("Edit Entry")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button("Save") { saveInlineEdit() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Merchant")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                    TextField("Merchant", text: $editMerchant)
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.textPrimary)
                        .textInputAutocapitalization(.words)
                    Divider()
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Amount")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                    HStack {
                        Text("$")
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.textTertiary)
                        TextField("0.00", text: $editAmount)
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.textPrimary)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                    }
                    Divider()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Budget")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)

                    HStack(spacing: 8) {
                        ForEach(BudgetBucket.allCases) { bucket in
                            Button {
                                editBucket = bucket
                            } label: {
                                VStack(spacing: 5) {
                                    Circle()
                                        .fill(bucket.color)
                                        .frame(width: 7, height: 7)
                                    Text(bucket == .fundamentals ? "NEEDS" : bucket == .fun ? "FUN" : "FUTURE")
                                        .font(.system(size: 10, weight: .bold))
                                        .kerning(0.6)
                                        .foregroundStyle(editBucket == bucket ? bucket.color : AppColors.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(editBucket == bucket ? bucket.color.opacity(0.08) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(editBucket == bucket ? bucket.color : AppColors.border, lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()

            // Delete button
            Button {
                if let expense = editingExpense {
                    deleteExpense(expense)
                    editingExpense = nil
                }
            } label: {
                Text("Delete Entry")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.overspend)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.overspend.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppColors.overspend.opacity(0.19), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(AppColors.secondaryBg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Collapsible Recurring

    private var collapsibleRecurringSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { recurringOpen.toggle() }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)

                        Text("Recurring · \(recurringExpenses.filter(\.isActive).count)")
                            .font(.system(size: 10, weight: .bold))
                            .kerning(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.textTertiary)

                        Text("\(recurringMonthlyTotal.formattedCurrency(code: appPreferences.currencyCode))/mo")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                            .monospacedDigit()
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(recurringOpen ? 180 : 0))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if recurringOpen {
                Divider()
                ForEach(Array(effectiveRecurringExpenses.enumerated()), id: \.element.id) { index, recurring in
                    if index > 0 {
                        Divider().padding(.leading, 34)
                    }
                    HStack(spacing: 10) {
                        Circle()
                            .fill(recurring.budgetBucket.color)
                            .frame(width: 5, height: 5)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(recurring.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)

                            Text("Monthly · \(recurring.budgetBucket.rawValue)")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }

                        Spacer()

                        Text(recurring.safeAmount.formattedCurrency(code: appPreferences.currencyCode))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    // MARK: - Collapsible Transaction List

    private var collapsibleTransactionSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { txOpen.toggle() }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)

                        Text("This Month · \(expenses.count)")
                            .font(.system(size: 10, weight: .bold))
                            .kerning(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(txOpen ? 180 : 0))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if txOpen {
                if expenses.isEmpty {
                    EmptyStateView()
                        .padding(.bottom, 20)
                } else {
                    if !searchText.isEmpty || selectedBucketFilter != nil {
                        Divider()
                        SearchBar(text: $searchText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }

                    Divider()

                    ExpenseListView(
                        expenses: expenses,
                        searchText: searchText,
                        bucketFilter: selectedBucketFilter,
                        onDeleteExpense: deleteExpense
                    )
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: - Submit Logic

    private func submitExpense(
        _ rawInput: String,
        source: Expense.SourceKind = .manual
    ) async -> Bool {
        guard !rawInput.isEmpty else { return false }
        diagnosticLogger.record(
            category: "expense.submit",
            message: "Started expense parsing",
            metadata: ["inputLength": "\(rawInput.count)"]
        )
        isProcessing = true
        showError = false
        errorMessage = nil

        do {
            let result = try await llmService.parseExpense(
                from: rawInput,
                allowedCategories: categoryManager.promptCategories,
                inputLanguage: appPreferences.inputLanguage,
                currencyCode: appPreferences.currencyCode
            )
            let resolved = categoryManager.resolve(
                raw: result.category,
                context: "\(result.merchant) \(rawInput)"
            )
            let signedAmount = result.signedAmount(fallbackInput: rawInput)
            let isIncomeTransaction = result.isIncome(fallbackInput: rawInput)
            let storageCategory = isIncomeTransaction ? "income" : resolved.storageKey
            let storageBucket: BudgetBucket = isIncomeTransaction ? .future : resolved.bucket

            let expense = Expense(
                merchant: result.merchant.normalizedMerchantName(),
                amount: signedAmount,
                category: storageCategory,
                bucket: storageBucket,
                isOverspent: isExpenseOverspent(amount: signedAmount),
                notes: rawInput,
                source: source,
                importedAt: source == .appleWalletSync ? .now : nil
            )

            let crossedIntoOverspent = didCrossIntoOverspent(
                bucket: storageBucket,
                adding: expense
            )

            modelContext.insert(expense)
            try modelContext.save()
            budgetEngine.markDataChanged()
            diagnosticLogger.record(
                category: "expense.submit",
                message: "Saved expense",
                metadata: [
                    "amount": String(format: "%.2f", signedAmount),
                    "category": storageCategory,
                    "budget": storageBucket.rawValue,
                    "isIncome": isIncomeTransaction ? "true" : "false",
                    "source": source.rawValue
                ]
            )

            recurringSuggestion = recurringSuggestionCandidate(for: expense)

            if crossedIntoOverspent {
                showOverspendTriggeredBanner(for: storageBucket)
            }

            HapticManager.success()
            isProcessing = false
            return true

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            diagnosticLogger.record(
                level: .error,
                category: "expense.submit",
                message: "Failed to save expense",
                metadata: ["error": error.localizedDescription]
            )
            HapticManager.warning()
            isProcessing = false

            // Auto-dismiss error after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation { showError = false }
            }
            return false
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var modelStatusBanner: some View {
        switch llmService.loadState {
        case .idle:
            EmptyView()

        case .downloading(let progress):
            let safeProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
            if safeProgress < 0.995 {
                HStack(spacing: 8) {
                    ProgressView(value: safeProgress)
                        .tint(AppColors.accent)
                    Text("Downloading AI model… \(Int(safeProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.secondaryBg)
                )
                .padding(.horizontal)
            } else {
                EmptyView()
            }

        case .loading:
            EmptyView()

        case .ready:
            EmptyView()

        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .thin))
                Text("Model error: \(msg)")
                    .font(.caption2)
            }
            .foregroundStyle(.red)
            .padding(.horizontal)
        }
    }

    private var incomePrompt: some View {
        Button {
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 14, weight: .thin))
                Text("Set your monthly income to see budget targets")
                    .font(.caption)
            }
            .foregroundStyle(AppColors.accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.accent.opacity(0.08))
            )
        }
        .padding(.horizontal)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .thin))
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(AppColors.overspend)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.overspend.opacity(0.08))
        )
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func overspentEntryBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .regular))
            Text(message)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.overspend)
        )
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func bucketStatusRow(_ status: BudgetEngine.BucketStatus) -> some View {
        BucketSummaryRow(
            status: status,
            isSelected: selectedBucketFilter == status.bucket,
            onTap: {
                selectedBucketFilter = (selectedBucketFilter == status.bucket) ? nil : status.bucket
            }
        )
    }

    private var inputDock: some View {
        DashboardInputDock(
            isProcessing: isProcessing,
            focusTrigger: composerFocusTrigger,
            onSubmit: { text in
                await submitExpense(text)
            },
            onCameraTap: {
                if !VNDocumentCameraViewController.isSupported {
                    presentTransientError(
                        ReceiptScannerError.unavailable.localizedDescription
                    )
                    return
                }
                showReceiptScanner = true
            }
        )
    }

    private func overspentSummaryRow(amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppColors.overspend)

                Text("Over Spent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.overspend)

                Spacer()

                Text(amount.formattedCurrency(code: appPreferences.currencyCode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.overspend)

                Text("/ \(0.0.formattedCurrency(code: appPreferences.currencyCode))")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AppColors.overspend)
                        .frame(width: safeWidth(geo.size.width))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.secondaryBg)
        )
    }

    private func recurringSummaryRow(amount: Double, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "repeat")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)

            Text("Recurring (\(count))")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(amount.formattedCurrency(code: appPreferences.currencyCode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text("/ month")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.secondaryBg)
        )
    }

    private func underspentSummaryRow(amount: Double, total: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.green)

            Text("Remaining This Month")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            Spacer()

            Text(amount.formattedCurrency(code: appPreferences.currencyCode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            Text("/ \(total.formattedCurrency(code: appPreferences.currencyCode))")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.secondaryBg)
        )
    }

    private func isExpenseOverspent(amount: Double) -> Bool {
        guard amount > 0 else { return false }
        guard budgetEngine.monthlyIncome > 0 else { return false }
        let projected = budgetEngine.totalSpent(
            expenses: expenses,
            recurringExpenses: recurringExpenses
        ) + amount
        return projected > budgetEngine.monthlyIncome
    }

    private func didCrossIntoOverspent(bucket: BudgetBucket, adding expense: Expense) -> Bool {
        guard expense.amount > 0 else { return false }

        let before = bucketStatuses(for: expenses, recurringExpenses: recurringExpenses)
        let after = bucketStatuses(for: expenses + [expense], recurringExpenses: recurringExpenses)

        let beforeStatus = before.first(where: { $0.bucket == bucket })
        let afterStatus = after.first(where: { $0.bucket == bucket })
        guard let afterStatus else { return false }
        return !(beforeStatus?.isOverspent ?? false) && afterStatus.isOverspent
    }

    private func bucketStatuses(
        for expenses: [Expense],
        recurringExpenses: [RecurringExpense]
    ) -> [BudgetEngine.BucketStatus] {
        budgetEngine.calculateStatus(
            expenses: expenses,
            recurringExpenses: recurringExpenses
        )
    }

    private func showOverspendTriggeredBanner(for bucket: BudgetBucket) {
        overspentBannerMessage = "\(bucket.rawValue) just went over budget."
        withAnimation(.easeOut(duration: 0.2)) {
            showOverspentBanner = true
        }
        HapticManager.warning()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeInOut(duration: 0.2)) {
                showOverspentBanner = false
            }
        }
    }

    private func safeWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func presentTransientError(_ message: String) {
        errorMessage = message
        showError = true

        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation { showError = false }
        }
    }

    private func recurringSuggestionCandidate(for newExpense: Expense) -> RecurringSuggestion? {
        guard newExpense.amount > 0 else { return nil }
        guard recurringExpenses.allSatisfy({
            $0.name.normalizedMerchantName() != newExpense.normalizedMerchant
        }) else { return nil }

        let calendar = Calendar.current
        let matching = (expenses + [newExpense]).filter {
            $0.amount > 0 && $0.normalizedMerchant == newExpense.normalizedMerchant
        }
        guard matching.count >= 2 else { return nil }

        let distinctMonths = Set(
            matching.map {
                calendar.dateComponents([.year, .month], from: $0.date)
            }
        )
        guard distinctMonths.count >= 2 else { return nil }

        let average = matching.reduce(0) { $0 + $1.amount } / Double(matching.count)
        let safeAverage = average.isFinite ? max(average, 0) : 0
        guard safeAverage > 0 else { return nil }

        return RecurringSuggestion(
            name: newExpense.normalizedMerchant,
            amount: safeAverage,
            bucket: newExpense.budgetBucket
        )
    }

    private func addSuggestedRecurringExpense() {
        guard let suggestion = recurringSuggestion else { return }
        let recurring = RecurringExpense(
            name: suggestion.name,
            amount: suggestion.amount,
            bucket: suggestion.bucket
        )
        modelContext.insert(recurring)
        do {
            try modelContext.save()
            budgetEngine.markDataChanged()
            HapticManager.success()
            diagnosticLogger.record(
                category: "recurring.suggestion",
                message: "Accepted recurring suggestion",
                metadata: [
                    "name": suggestion.name,
                    "amount": String(format: "%.2f", suggestion.amount),
                    "budget": suggestion.bucket.rawValue
                ]
            )
        } catch {
            print("Failed to save suggested recurring expense: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "recurring.suggestion",
                message: "Failed to save recurring suggestion",
                metadata: ["error": error.localizedDescription]
            )
        }
        recurringSuggestion = nil
    }

    private func deleteExpense(_ expense: Expense) {
        modelContext.delete(expense)
        do {
            try modelContext.save()
            budgetEngine.markDataChanged()
            HapticManager.warning()
            diagnosticLogger.record(
                category: "expense.delete",
                message: "Deleted expense",
                metadata: [
                    "amount": String(format: "%.2f", expense.amount),
                    "category": expense.category,
                    "budget": expense.bucket
                ]
            )
        } catch {
            print("Failed to delete expense: \(error)")
            diagnosticLogger.record(
                level: .error,
                category: "expense.delete",
                message: "Failed to delete expense",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func scheduleStartupMaintenance() async {
        guard !didRunStartupMaintenance else { return }
        didRunStartupMaintenance = true

        // Let first paint and first interactions (keyboard tap) win.
        try? await Task.sleep(for: .milliseconds(900))

        await runMigrationsInChunks()
    }

    private func runMigrationsInChunks() async {
        if !didRunCategoryConsistencyFixV2 {
            await migrateCategoryConsistencyChunked()
        }
        if !didNormalizeMerchantsV1 {
            await migrateMerchantCapitalizationChunked()
        }
    }

    private func migrateCategoryConsistencyChunked() async {
        let chunkSize = 50
        var didMutate = false
        var processed = 0

        for expense in expenses {
            let context = "\(expense.category) \(expense.merchant) \(expense.notes)"
            let resolved = categoryManager.resolve(raw: expense.category, context: context)

            if expense.category != resolved.storageKey {
                expense.category = resolved.storageKey
                expense.touchUpdatedAt()
                didMutate = true
            }
            if expense.bucket != resolved.bucket.rawValue {
                expense.bucket = resolved.bucket.rawValue
                expense.touchUpdatedAt()
                didMutate = true
            }

            processed += 1
            if processed % chunkSize == 0 {
                await Task.yield()
            }
        }

        if didMutate {
            do {
                try modelContext.save()
                budgetEngine.markDataChanged()
            } catch {
                diagnosticLogger.record(
                    level: .error,
                    category: "maintenance.category",
                    message: "Failed category consistency migration",
                    metadata: ["error": error.localizedDescription]
                )
            }
        }

        didRunCategoryConsistencyFixV2 = true
    }

    private func migrateMerchantCapitalizationChunked() async {
        let chunkSize = 50
        var didMutate = false
        var processed = 0

        for expense in expenses {
            let normalized = expense.merchant.normalizedMerchantName()
            if normalized != expense.merchant {
                expense.merchant = normalized
                expense.touchUpdatedAt()
                didMutate = true
            }

            processed += 1
            if processed % chunkSize == 0 {
                await Task.yield()
            }
        }

        if didMutate {
            do {
                try modelContext.save()
                budgetEngine.markDataChanged()
            } catch {
                diagnosticLogger.record(
                    level: .error,
                    category: "maintenance.merchant",
                    message: "Failed merchant normalization migration",
                    metadata: ["error": error.localizedDescription]
                )
            }
        }

        didNormalizeMerchantsV1 = true
    }

    private func refreshDashboard() async {
        budgetEngine.markDataChanged()
        await runMigrationsInChunks()
        HapticManager.light()
    }

    private func consumeLaunchActionIfNeeded() {
        guard let action = launchAction else { return }

        switch action.kind {
        case .focusComposer:
            composerFocusTrigger += 1
        case .scanReceipt:
            if VNDocumentCameraViewController.isSupported {
                showReceiptScanner = true
            } else {
                presentTransientError(ReceiptScannerError.unavailable.localizedDescription)
            }
        }

        launchAction = nil
    }

    private func presentModelOnboardingIfNeeded() async {
        guard llmService.supportsLocalModel else { return }
        guard didCompleteAppOnboarding else { return }
        guard !didCompleteModelOnboarding else { return }
        guard !showModelOnboarding else { return }

        try? await Task.sleep(for: .milliseconds(350))

        guard didCompleteAppOnboarding else { return }
        guard !didCompleteModelOnboarding else { return }
        guard !showReceiptScanner && editingExpense == nil else { return }

        showModelOnboarding = true
    }
}
