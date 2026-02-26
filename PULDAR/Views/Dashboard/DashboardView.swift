import SwiftUI
import SwiftData

/// The main screen — orchestrates the entire expense-tracking flow.
///
/// Layout (top-to-bottom, Notion-style):
///   1. Donut chart  →  visual dashboard
///   2. Bucket bars   →  per-bucket progress
///   3. Text input    →  primary user intent
///   4. Search bar    →  filter & highlight
///   5. Expense list  →  progressive disclosure
struct DashboardView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(UsageTracker.self) private var usageTracker

    // MARK: - SwiftData Query

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    // MARK: - Local State

    @State private var isProcessing = false
    @State private var searchText = ""
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showModelOnboarding = false
    @State private var errorMessage: String?
    @State private var showError = false
    @AppStorage("didCompleteModelOnboarding") private var didCompleteModelOnboarding = false
    @AppStorage("didRunCategoryConsistencyFixV2") private var didRunCategoryConsistencyFixV2 = false
    @AppStorage("didNormalizeMerchantsV1") private var didNormalizeMerchantsV1 = false
    @State private var didRunStartupMaintenance = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Model Status Banner ────────────────────────────
                    modelStatusBanner

                    // ── 1. Donut Chart ─────────────────────────────────
                    let statuses = budgetEngine.calculateStatus(expenses: expenses)
                    let monthlyOverspent = budgetEngine.monthlyOverspentAmount(expenses: expenses)

                    BucketDonutChart(statuses: statuses)
                        .padding(.top, 4)

                    // ── 2. Bucket Progress Bars ────────────────────────
                    VStack(spacing: 10) {
                        ForEach(statuses) { status in
                            BucketSummaryRow(status: status)
                        }
                    }
                    .padding(.horizontal)

                    if monthlyOverspent > 0 {
                        overspentSummaryRow(amount: monthlyOverspent)
                            .padding(.horizontal)
                    }

                    // ── Income Prompt ──────────────────────────────────
                    if budgetEngine.monthlyIncome == 0 {
                        incomePrompt
                    }

                    Divider()
                        .padding(.horizontal, 24)

                    // ── 3. Expense Input ───────────────────────────────
                    ExpenseInputView(
                        isProcessing: isProcessing,
                        isLocked: !storeKit.isPro && usageTracker.isAtLimit,
                        onSubmit: submitExpense
                    )

                    // Usage indicator (free tier only)
                    if !storeKit.isPro {
                        usageIndicator
                    }

                    // Error toast
                    if showError, let msg = errorMessage {
                        errorBanner(msg)
                    }

                    // ── 4. Search ──────────────────────────────────────
                    if !expenses.isEmpty {
                        SearchBar(text: $searchText)
                            .padding(.horizontal)
                    }

                    // ── 5. Expense List / Empty State ──────────────────
                    if expenses.isEmpty {
                        EmptyStateView()
                    } else {
                        ExpenseListView(
                            expenses: expenses,
                            searchText: searchText,
                            onDeleteExpense: deleteExpense
                        )
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("PULDAR")
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
            .task {
                if !didCompleteModelOnboarding {
                    showModelOnboarding = true
                }
            }
            .task {
                runStartupMaintenanceIfNeeded()
            }
            .onChange(of: expenses.count) {
                usageTracker.reconcile(with: expenses)
                if !didRunCategoryConsistencyFixV2 {
                    migrateCategoryConsistencyIfNeeded()
                }
                if !didNormalizeMerchantsV1 {
                    migrateMerchantCapitalizationIfNeeded()
                }
            }
        }
    }

    // MARK: - Submit Logic

    private func submitExpense(_ rawInput: String) async -> Bool {
        // Gate: paywall check
        if !storeKit.isPro && usageTracker.isAtLimit {
            showPaywall = true
            HapticManager.warning()
            return false
        }

        guard !rawInput.isEmpty else { return false }
        isProcessing = true
        showError = false
        errorMessage = nil

        do {
            let result = try await llmService.parseExpense(
                from: rawInput,
                allowedCategories: categoryManager.promptCategories
            )
            let resolved = categoryManager.resolve(
                raw: result.category,
                context: "\(result.merchant) \(rawInput)"
            )
            let signedAmount = result.signedAmount(fallbackInput: rawInput)

            let expense = Expense(
                merchant: result.merchant.normalizedMerchantName(),
                amount: signedAmount,
                category: resolved.storageKey,
                bucket: resolved.bucket,
                isOverspent: isExpenseOverspent(amount: signedAmount),
                notes: rawInput
            )

            modelContext.insert(expense)
            try modelContext.save()

            // Track usage (free tier only)
            if !storeKit.isPro {
                usageTracker.recordInput()
            }

            HapticManager.success()
            isProcessing = false
            return true

        } catch {
            errorMessage = error.localizedDescription
            showError = true
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
            ForEach(0..<AppConstants.freeInputsPerWeek, id: \.self) { i in
                Circle()
                    .fill(
                        i < usageTracker.currentCount
                            ? AppColors.accent
                            : Color(.systemGray4)
                    )
                    .frame(width: 6, height: 6)
            }

            Text("\(usageTracker.remainingFreeInputs) left")
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

                Text(amount, format: .currency(code: "USD"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.overspend)

                Text("/ \(0, format: .currency(code: "USD"))")
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

    private func isExpenseOverspent(amount: Double) -> Bool {
        guard amount > 0 else { return false }
        guard budgetEngine.monthlyIncome > 0 else { return false }
        let projected = budgetEngine.totalSpent(expenses: expenses) + amount
        return projected > budgetEngine.monthlyIncome
    }

    private func safeWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func deleteExpense(_ expense: Expense) {
        modelContext.delete(expense)
        do {
            try modelContext.save()
            HapticManager.warning()
        } catch {
            print("Failed to delete expense: \(error)")
        }
    }

    private func runStartupMaintenanceIfNeeded() {
        guard !didRunStartupMaintenance else { return }
        didRunStartupMaintenance = true

        usageTracker.reconcile(with: expenses)
        migrateCategoryConsistencyIfNeeded()
        migrateMerchantCapitalizationIfNeeded()
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
                didMutate = true
            }

            if expense.bucket != resolved.bucket.rawValue {
                expense.bucket = resolved.bucket.rawValue
                didMutate = true
            }
        }

        if didMutate {
            do {
                try modelContext.save()
            } catch {
                print("Failed category consistency migration: \(error)")
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
                didMutate = true
            }
        }

        if didMutate {
            do {
                try modelContext.save()
            } catch {
                print("Failed merchant capitalization migration: \(error)")
            }
        }

        didNormalizeMerchantsV1 = true
    }
}
