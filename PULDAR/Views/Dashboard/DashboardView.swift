import SwiftUI
import SwiftData
import VisionKit

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
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(UsageTracker.self) private var usageTracker
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
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showModelOnboarding = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var overspentBannerMessage: String?
    @State private var showOverspentBanner = false
    @State private var recurringSuggestion: RecurringSuggestion?
    @State private var showReceiptScanner = false
    @State private var composerFocusTrigger = 0
    @AppStorage("didCompleteModelOnboarding") private var didCompleteModelOnboarding = false
    @AppStorage("didRunCategoryConsistencyFixV2") private var didRunCategoryConsistencyFixV2 = false
    @AppStorage("didNormalizeMerchantsV1") private var didNormalizeMerchantsV1 = false
    @State private var didRunStartupMaintenance = false

    private var effectiveRecurringExpenses: [RecurringExpense] {
        storeKit.isPro ? recurringExpenses : []
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
        storeKit.isPro ? budgetEngine.recurringTotal(recurringExpenses) : 0
    }

    private var dashboardMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 900 : .infinity
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                dashboardContent
                    .padding(.vertical)
                    .frame(maxWidth: dashboardMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .refreshable {
                await refreshDashboard()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("PULDAR")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputDock
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.light()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .thin))
                    }
                }
            }
            .fullScreenCover(isPresented: $showModelOnboarding) {
                ModelDownloadOnboardingView {
                    didCompleteModelOnboarding = true
                    showModelOnboarding = false
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
            .task {
                if !didCompleteModelOnboarding {
                    showModelOnboarding = true
                }
            }
            .task {
                await storeKit.checkEntitlement()
            }
            .task {
                await scheduleStartupMaintenance()
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await storeKit.checkEntitlement() }
            }
            .onChange(of: expenses.count) {
                usageTracker.reconcile(with: expenses)
            }
            .onAppear {
                consumeLaunchActionIfNeeded()
            }
            .onChange(of: launchAction?.id) {
                consumeLaunchActionIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 20) {
            modelStatusBanner

            BucketDonutChart(
                statuses: bucketStatuses,
                selectedBucket: selectedBucketFilter,
                onBucketSelected: { selectedBucketFilter = $0 }
            )
            .padding(.top, 4)

            VStack(spacing: 10) {
                ForEach(bucketStatuses) { status in
                    bucketStatusRow(status)
                }
            }
            .padding(.horizontal)

            if monthlyOverspentAmount > 0 {
                overspentSummaryRow(amount: monthlyOverspentAmount)
                    .padding(.horizontal)
            }
            if monthlyUnderspentAmount > 0 {
                underspentSummaryRow(
                    amount: monthlyUnderspentAmount,
                    total: monthlySpendCapacity
                )
                    .padding(.horizontal)
            }

            if recurringMonthlyTotal > 0 {
                recurringSummaryRow(
                    amount: recurringMonthlyTotal,
                    count: recurringExpenses.filter(\.isActive).count
                )
                .padding(.horizontal)
            }

            if budgetEngine.monthlyIncome == 0 {
                incomePrompt
            }

            Divider()
                .padding(.horizontal, 24)

            if let selectedBucketFilter {
                HStack(spacing: 8) {
                    Text("Showing \(selectedBucketFilter.rawValue)")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Button("Clear") {
                        self.selectedBucketFilter = nil
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal)
            }

            if showError, let msg = errorMessage {
                errorBanner(msg)
            }
            if showOverspentBanner, let message = overspentBannerMessage {
                overspentEntryBanner(message)
            }

            if !expenses.isEmpty {
                SearchBar(text: $searchText)
                    .padding(.horizontal)
            }

            if expenses.isEmpty {
                EmptyStateView()
            } else {
                ExpenseListView(
                    expenses: expenses,
                    searchText: searchText,
                    bucketFilter: selectedBucketFilter,
                    onDeleteExpense: deleteExpense
                )
                .padding(.horizontal)
            }

            Spacer(minLength: 140)
        }
    }

    // MARK: - Submit Logic

    private func submitExpense(
        _ rawInput: String,
        source: Expense.SourceKind = .manual
    ) async -> Bool {
        // Gate: paywall check
        if !storeKit.isPro && usageTracker.isAtLimit {
            showPaywall = true
            HapticManager.warning()
            diagnosticLogger.record(
                level: .warning,
                category: "expense.submit",
                message: "Blocked expense submission at free limit"
            )
            return false
        }

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

            // Track usage (free tier only)
            if !storeKit.isPro {
                usageTracker.recordInput()
            }

            if storeKit.isPro {
                recurringSuggestion = recurringSuggestionCandidate(for: expense)
            }

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
            showSettings = true
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

    private var usageIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<AppConstants.freeInputsPerMonth, id: \.self) { i in
                Circle()
                    .fill(
                        i < usageTracker.currentCount
                            ? AppColors.accent
                            : Color(.systemGray4)
                    )
                    .frame(width: 6, height: 6)
            }

            Text("\(usageTracker.remainingFreeInputs) Monthly Entries Remaining")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.leading, 4)
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
        VStack(spacing: 8) {
            ExpenseInputView(
                isProcessing: isProcessing,
                isLocked: !storeKit.isPro && usageTracker.isAtLimit,
                onSubmit: submitExpense,
                focusTrigger: composerFocusTrigger,
                onLockedTap: {
                    if !storeKit.isPro && usageTracker.isAtLimit {
                        showPaywall = true
                    }
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

            if !storeKit.isPro {
                usageIndicator
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 24,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 24
                ),
                style: .continuous
            )
                .fill(AppColors.secondaryBg)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
                .ignoresSafeArea()
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
            recurringExpenses: storeKit.isPro ? recurringExpenses : []
        ) + amount
        return projected > budgetEngine.monthlyIncome
    }

    private func didCrossIntoOverspent(bucket: BudgetBucket, adding expense: Expense) -> Bool {
        guard expense.amount > 0 else { return false }

        let recurring = storeKit.isPro ? recurringExpenses : []
        let before = bucketStatuses(for: expenses, recurringExpenses: recurring)
        let after = bucketStatuses(for: expenses + [expense], recurringExpenses: recurring)

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

    private func runStartupMaintenanceIfNeeded() {
        guard !didRunStartupMaintenance else { return }
        didRunStartupMaintenance = true

        usageTracker.reconcile(with: expenses)
        migrateCategoryConsistencyIfNeeded()
        migrateMerchantCapitalizationIfNeeded()
    }

    private func scheduleStartupMaintenance() async {
        guard !didRunStartupMaintenance else { return }
        // Let first paint and first interactions (keyboard tap) win.
        try? await Task.sleep(for: .milliseconds(900))
        await MainActor.run {
            runStartupMaintenanceIfNeeded()
        }
    }

    private func refreshDashboard() async {
        await MainActor.run {
            budgetEngine.markDataChanged()
            usageTracker.reconcile(with: expenses)

            if !didRunCategoryConsistencyFixV2 {
                migrateCategoryConsistencyIfNeeded()
            }
            if !didNormalizeMerchantsV1 {
                migrateMerchantCapitalizationIfNeeded()
            }

            HapticManager.light()
        }
    }

    private func migrateCategoryConsistencyIfNeeded() {
        guard !didRunCategoryConsistencyFixV2 else { return }
        guard !expenses.isEmpty else { return }

        var didMutate = false

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
        }

        if didMutate {
            do {
                try modelContext.save()
                budgetEngine.markDataChanged()
            } catch {
                print("Failed category consistency migration: \(error)")
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

    private func migrateMerchantCapitalizationIfNeeded() {
        guard !didNormalizeMerchantsV1 else { return }
        guard !expenses.isEmpty else { return }

        var didMutate = false
        for expense in expenses {
            let normalized = expense.merchant.normalizedMerchantName()
            if normalized != expense.merchant {
                expense.merchant = normalized
                expense.touchUpdatedAt()
                didMutate = true
            }
        }

        if didMutate {
            do {
                try modelContext.save()
                budgetEngine.markDataChanged()
            } catch {
                print("Failed merchant capitalization migration: \(error)")
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
}
