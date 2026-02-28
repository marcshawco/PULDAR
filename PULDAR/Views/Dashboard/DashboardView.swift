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
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(UsageTracker.self) private var usageTracker

    // MARK: - SwiftData Query

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    // MARK: - Local State

    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var searchText = ""
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Model Status Banner ────────────────────────────
                    modelStatusBanner

                    // ── 1. Donut Chart ─────────────────────────────────
                    let statuses = budgetEngine.calculateStatus(expenses: expenses)

                    BucketDonutChart(statuses: statuses)
                        .padding(.top, 4)

                    // ── 2. Bucket Progress Bars ────────────────────────
                    VStack(spacing: 10) {
                        ForEach(statuses) { status in
                            BucketSummaryRow(status: status)
                        }
                    }
                    .padding(.horizontal)

                    // ── Income Prompt ──────────────────────────────────
                    if budgetEngine.monthlyIncome == 0 {
                        incomePrompt
                    }

                    Divider()
                        .padding(.horizontal, 24)

                    // ── 3. Expense Input ───────────────────────────────
                    ExpenseInputView(
                        inputText: $inputText,
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
                            searchText: searchText
                        )
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                await llmService.loadModel()
            }
            .task {
                await storeKit.loadProducts()
                await storeKit.checkEntitlement()
            }
        }
    }

    // MARK: - Submit Logic

    private func submitExpense() {
        // Gate: paywall check
        if !storeKit.isPro && usageTracker.isAtLimit {
            showPaywall = true
            HapticManager.warning()
            return
        }

        let rawInput = inputText.trimmingCharacters(in: .whitespaces)
        guard !rawInput.isEmpty else { return }

        // Clear input immediately for snappy UX
        inputText = ""
        isProcessing = true
        showError = false
        errorMessage = nil

        Task {
            do {
                let result = try await llmService.parseExpense(from: rawInput)

                let category = ExpenseCategory.resolve(result.category)

                let expense = Expense(
                    merchant: result.merchant,
                    amount: abs(result.amount),  // Ensure positive
                    category: category.rawValue,
                    bucket: category.bucket,
                    notes: rawInput
                )

                modelContext.insert(expense)

                // Track usage (free tier only)
                if !storeKit.isPro {
                    usageTracker.recordInput()
                }

                HapticManager.success()

            } catch {
                errorMessage = error.localizedDescription
                inputText = rawInput   // Restore on failure
                showError = true
                HapticManager.warning()

                // Auto-dismiss error after 5 seconds
                try? await Task.sleep(for: .seconds(5))
                withAnimation { showError = false }
            }

            isProcessing = false
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var modelStatusBanner: some View {
        switch llmService.loadState {
        case .idle:
            EmptyView()

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(AppColors.accent)
                Text("Downloading AI model… \(Int(progress * 100))%")
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

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading AI model…")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal)

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
}
