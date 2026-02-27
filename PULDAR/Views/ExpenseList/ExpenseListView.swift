import SwiftUI
import SwiftData

/// Progressively-disclosed list of recent expense logs.
///
/// Filters in real time when `searchText` is non-empty and
/// delegates yellow highlighting down to each row.
struct ExpenseListView: View {
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(\.modelContext) private var modelContext
    let expenses: [Expense]
    let searchText: String
    let bucketFilter: BudgetBucket?
    let onDeleteExpense: (Expense) -> Void

    /// Show 10 items initially, load more on scroll.
    @State private var visibleCount = 10
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var editingExpense: Expense?
    @State private var editMerchant = ""
    @State private var editAmount = ""
    @State private var editCategory = ""
    @State private var editBucket: BudgetBucket = .fun
    @State private var editDate = Date.now
    @State private var editError: String?
    @State private var dateFilterRange: ClosedRange<Date>?
    @State private var textFilterOnly = ""

    private var filteredExpenses: [Expense] {
        expenses.filter { expense in
            if let dateFilterRange {
                guard dateFilterRange.contains(expense.date) else { return false }
            }

            let matchesBucket = bucketFilter.map { expense.budgetBucket == $0 } ?? true
            guard matchesBucket else { return false }

            guard !textFilterOnly.isEmpty else { return true }
            let query = textFilterOnly.lowercased()
            let categoryDisplay = categoryManager
                .displayName(forStoredCategory: expense.category)
                .lowercased()
            return expense.normalizedMerchant.lowercased().contains(query)
                || expense.category.lowercased().contains(query)
                || categoryDisplay.contains(query)
                || expense.notes.lowercased().contains(query)
                || expense.budgetBucket.rawValue.lowercased().contains(query)
                || (expense.isOverspent && "overspent".contains(query))
        }
    }

    private var visibleExpenses: [Expense] {
        Array(filteredExpenses.prefix(visibleCount))
    }

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(visibleExpenses) { expense in
                ExpenseRowView(
                    expense: expense,
                    highlightText: searchText,
                    onEdit: { beginEditing(expense) }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        beginEditing(expense)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(AppColors.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDeleteExpense(expense)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // "Load more" trigger
            if visibleCount < filteredExpenses.count {
                ProgressView()
                    .padding(.vertical, 12)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.3)) {
                            visibleCount += 10
                        }
                    }
            }
        }
        .onAppear {
            debouncedSearchText = searchText
            updateFilters(from: searchText)
        }
        .onChange(of: searchText) {
            visibleCount = 10   // Reset pagination on new search
            debounceTask?.cancel()

            let pending = searchText
            if pending.isEmpty {
                debouncedSearchText = ""
                updateFilters(from: "")
                return
            }

            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    debouncedSearchText = pending
                    updateFilters(from: pending)
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .sheet(item: $editingExpense) { _ in
            NavigationStack {
                Form {
                    TextField("Merchant", text: $editMerchant)
                        .textInputAutocapitalization(.words)

                    TextField("Amount", text: $editAmount)
                        .keyboardType(.decimalPad)

                    Picker("Category", selection: $editCategory) {
                        ForEach(editCategoryOptions, id: \.storageKey) { option in
                            Text(option.label).tag(option.storageKey)
                        }
                    }

                    Picker("Bucket", selection: $editBucket) {
                        ForEach(BudgetBucket.allCases) { bucket in
                            Text(bucket.rawValue).tag(bucket)
                        }
                    }

                    DatePicker("Date", selection: $editDate, displayedComponents: .date)

                    if let editError {
                        Text(editError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .navigationTitle("Edit Transaction")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingExpense = nil
                            editError = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEditingExpense()
                        }
                    }
                }
            }
        }
    }

    private func beginEditing(_ expense: Expense) {
        editingExpense = expense
        editMerchant = expense.normalizedMerchant
        editAmount = String(format: "%.2f", abs(expense.amount))
        editCategory = expense.category
        editBucket = expense.budgetBucket
        editDate = expense.date
        editError = nil
    }

    private func saveEditingExpense() {
        guard let expense = editingExpense else { return }
        let trimmedMerchant = editMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else {
            editError = "Merchant is required."
            return
        }
        guard let amount = Double(editAmount), amount.isFinite, amount >= 0 else {
            editError = "Amount must be a valid number."
            return
        }

        expense.merchant = trimmedMerchant.normalizedMerchantName()
        expense.amount = (editCategory == "income") ? -abs(amount) : (expense.amount < 0 ? -abs(amount) : abs(amount))
        expense.category = editCategory
        expense.bucket = editBucket.rawValue
        expense.date = editDate

        do {
            try modelContext.save()
            editingExpense = nil
            editError = nil
            HapticManager.success()
        } catch {
            editError = "Could not save changes."
        }
    }

    private struct EditCategoryOption {
        let storageKey: String
        let label: String
    }

    private var editCategoryOptions: [EditCategoryOption] {
        var options: [EditCategoryOption] = ExpenseCategory.allCases.map {
            .init(storageKey: $0.rawValue, label: categoryManager.displayName(forCanonicalKey: $0.rawValue))
        }
        options.append(.init(storageKey: "income", label: "Income"))
        for custom in categoryManager.customCategories {
            options.append(.init(storageKey: custom.key, label: custom.name))
        }
        return options
    }

    private func updateFilters(from query: String) {
        let parsed = parseDateFilter(query)
        dateFilterRange = parsed.range
        textFilterOnly = parsed.remainingText
    }

    private func parseDateFilter(_ query: String) -> (range: ClosedRange<Date>?, remainingText: String) {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return (nil, "") }

        let calendar = Calendar.current
        let now = Date.now
        var remaining = lower

        func startOfDay(_ date: Date) -> Date {
            calendar.startOfDay(for: date)
        }
        func dayRange(_ date: Date) -> ClosedRange<Date> {
            let start = startOfDay(date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start...end
        }
        func monthRange(_ date: Date) -> ClosedRange<Date>? {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            guard let start else { return nil }
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return start...end
        }

        var range: ClosedRange<Date>?
        let phraseRanges: [(String, () -> ClosedRange<Date>?)] = [
            ("today", { dayRange(now) }),
            ("yesterday", {
                guard let d = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
                return dayRange(d)
            }),
            ("this week", {
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
                return interval.start...interval.end
            }),
            ("last week", {
                guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
                      let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
                      let interval = calendar.dateInterval(of: .weekOfYear, for: prev) else {
                    return nil
                }
                return interval.start...interval.end
            }),
            ("this month", { monthRange(now) }),
            ("last month", {
                guard let prev = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
                return monthRange(prev)
            })
        ]

        for (phrase, provider) in phraseRanges where remaining.contains(phrase) {
            range = provider()
            remaining = remaining.replacingOccurrences(of: phrase, with: "")
            break
        }

        if range == nil {
            let monthNames = DateFormatter().monthSymbols?.map { $0.lowercased() } ?? []
            for (idx, monthName) in monthNames.enumerated() where remaining.contains(monthName) {
                var comps = calendar.dateComponents([.year], from: now)
                comps.month = idx + 1
                comps.day = 1
                if let monthDate = calendar.date(from: comps), let parsed = monthRange(monthDate) {
                    range = parsed
                    remaining = remaining.replacingOccurrences(of: monthName, with: "")
                }
                break
            }
        }

        let cleaned = remaining
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (range, cleaned)
    }
}
