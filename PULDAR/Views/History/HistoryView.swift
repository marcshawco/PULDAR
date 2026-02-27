import SwiftUI
import SwiftData

/// Historical reporting by month with CSV export.
struct HistoryView: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(StoreKitManager.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var selectedMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedCategoryFilter = "All"
    @State private var selectedDateRange: DateRangeFilter = .month
    @State private var customStartDate = Calendar.current.startOfDay(for: .now)
    @State private var customEndDate = Date()
    @State private var minAmountText = ""
    @State private var maxAmountText = ""
    @State private var merchantFilter = ""
    @State private var groupingMode: GroupingMode = .day
    @State private var sortMode: SortMode = .newest
    @State private var exportURL: URL?
    @State private var showPaywall = false
    @AppStorage("autoMonthlyCSVExportEnabled") private var autoMonthlyCSVExportEnabled = false
    @AppStorage("lastAutoMonthlyCSVExportKey") private var lastAutoMonthlyCSVExportKey = ""

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

    private var selectedMonthExpenses: [Expense] {
        let calendar = Calendar.current
        return expenses.filter {
            calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var categoryFilterOptions: [String] {
        var labels = Set<String>()
        for expense in selectedMonthExpenses {
            labels.insert(categoryManager.displayName(forStoredCategory: expense.category))
        }
        return ["All"] + labels.sorted()
    }

    private var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        var values = selectedMonthExpenses

        if selectedCategoryFilter != "All" {
            values = values.filter {
                categoryManager.displayName(forStoredCategory: $0.category) == selectedCategoryFilter
            }
        }

        let trimmedMerchant = merchantFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMerchant.isEmpty {
            let needle = trimmedMerchant.lowercased()
            values = values.filter {
                $0.normalizedMerchant.lowercased().contains(needle)
            }
        }

        if let minValue = Double(minAmountText), minValue.isFinite {
            values = values.filter { $0.amount >= minValue }
        }

        if let maxValue = Double(maxAmountText), maxValue.isFinite {
            values = values.filter { $0.amount <= maxValue }
        }

        switch selectedDateRange {
        case .month:
            break
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -7, to: .now) else { break }
            values = values.filter { $0.date >= start && $0.date <= .now }
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -30, to: .now) else { break }
            values = values.filter { $0.date >= start && $0.date <= .now }
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let endDay = calendar.startOfDay(for: max(customStartDate, customEndDate))
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? endDay
            values = values.filter { $0.date >= start && $0.date <= end }
        }

        return sorted(values)
    }

    private var groupedExpenses: [ExpenseGroup] {
        let calendar = Calendar.current

        switch groupingMode {
        case .day:
            let groups = Dictionary(grouping: filteredExpenses) { expense in
                calendar.startOfDay(for: expense.date)
            }
            return groups
                .keys
                .sorted(by: >)
                .map { day in
                    ExpenseGroup(
                        title: day.formatted(date: .abbreviated, time: .omitted),
                        items: sorted(groups[day] ?? [])
                    )
                }

        case .category:
            let groups = Dictionary(grouping: filteredExpenses) { expense in
                categoryManager.displayName(forStoredCategory: expense.category)
            }
            return sortGroupKeys(Array(groups.keys), groups: groups).map { key in
                ExpenseGroup(title: key, items: sorted(groups[key] ?? []))
            }

        case .merchant:
            let groups = Dictionary(grouping: filteredExpenses) { expense in
                expense.normalizedMerchant
            }
            return sortGroupKeys(Array(groups.keys), groups: groups).map { key in
                ExpenseGroup(title: key, items: sorted(groups[key] ?? []))
            }
        }
    }

    private var selectedStatuses: [BudgetEngine.BucketStatus] {
        budgetEngine.calculateStatus(expenses: filteredExpenses, for: selectedMonth)
    }

    private var selectedTotal: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Month") {
                    Picker("Selected month", selection: $selectedMonth) {
                        ForEach(monthOptions, id: \.self) { month in
                            Text(monthLabel(month)).tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Filters") {
                    Picker("Category", selection: $selectedCategoryFilter) {
                        ForEach(categoryFilterOptions, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }

                    Picker("Date Range", selection: $selectedDateRange) {
                        ForEach(DateRangeFilter.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }

                    if selectedDateRange == .custom {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                    }

                    HStack {
                        TextField("Min Amount", text: $minAmountText)
                            .keyboardType(.decimalPad)
                        TextField("Max Amount", text: $maxAmountText)
                            .keyboardType(.decimalPad)
                    }

                    TextField("Merchant", text: $merchantFilter)
                        .textInputAutocapitalization(.words)
                }

                Section("View") {
                    Picker("Group", selection: $groupingMode) {
                        ForEach(GroupingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Summary") {
                    LabeledContent("Total", value: selectedTotal.formatted(.currency(code: "USD")))
                    ForEach(selectedStatuses) { status in
                        HStack {
                            Label(status.bucket.rawValue, systemImage: status.bucket.icon)
                            Spacer()
                            Text(status.spent, format: .currency(code: "USD"))
                        }
                        .foregroundStyle(status.isOverspent ? AppColors.overspend : AppColors.textPrimary)
                    }
                }

                Section("Export") {
                    if store.isPro {
                        Button("Export Selected Month (CSV)") {
                            exportCSV(for: filteredExpenses, scope: monthLabel(selectedMonth))
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
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Unlock Pro (\(AppConstants.proPrice))", systemImage: "lock.open")
                        }
                    }
                }

                Section("Entries") {
                    if filteredExpenses.isEmpty {
                        Text("No entries match your filters.")
                            .foregroundStyle(AppColors.textTertiary)
                    } else {
                        ForEach(groupedExpenses) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textSecondary)

                                ForEach(group.items) { expense in
                                    expenseRow(expense)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .onAppear {
                if let first = monthOptions.first {
                    selectedMonth = first
                }
                syncFiltersForSelectedMonth()
                runAutoMonthlyExportIfNeeded()
            }
            .onChange(of: selectedMonth) {
                syncFiltersForSelectedMonth()
            }
            .onChange(of: autoMonthlyCSVExportEnabled) {
                runAutoMonthlyExportIfNeeded()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    @ViewBuilder
    private func expenseRow(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(expense.normalizedMerchant)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(expense.amount, format: .currency(code: "USD"))
                    .foregroundStyle(expense.amount < 0 ? .green : AppColors.textPrimary)
            }
            HStack(spacing: 10) {
                Text(categoryManager.displayName(forStoredCategory: expense.category))
                if expense.isOverspent {
                    Text("Overspent")
                        .foregroundStyle(AppColors.overspend)
                }
                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteExpense(expense)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide))
    }

    private func sorted(_ values: [Expense]) -> [Expense] {
        switch sortMode {
        case .newest:
            return values.sorted { $0.date > $1.date }
        case .largest:
            return values.sorted { abs($0.amount) > abs($1.amount) }
        case .alphabetical:
            return values.sorted { $0.normalizedMerchant.localizedCaseInsensitiveCompare($1.normalizedMerchant) == .orderedAscending }
        }
    }

    private func sortGroupKeys(_ keys: [String], groups: [String: [Expense]]) -> [String] {
        switch sortMode {
        case .newest:
            return keys.sorted { lhs, rhs in
                let left = groups[lhs]?.map(\.date).max() ?? .distantPast
                let right = groups[rhs]?.map(\.date).max() ?? .distantPast
                return left > right
            }
        case .largest:
            return keys.sorted { lhs, rhs in
                let left = groups[lhs]?.reduce(0) { $0 + abs($1.amount) } ?? 0
                let right = groups[rhs]?.reduce(0) { $0 + abs($1.amount) } ?? 0
                return left > right
            }
        case .alphabetical:
            return keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    private func syncFiltersForSelectedMonth() {
        if !categoryFilterOptions.contains(selectedCategoryFilter) {
            selectedCategoryFilter = "All"
        }

        let calendar = Calendar.current
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedMonth)
        ) ?? selectedMonth
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? selectedMonth

        customStartDate = monthStart
        customEndDate = monthEnd
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

        let safeScope = scope.replacingOccurrences(of: "[^a-zA-Z0-9_]+", with: "_", options: .regularExpression)
        let filename = "puldar_\(safeScope.lowercased()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            print("Failed to export CSV: \(error)")
        }
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func deleteExpense(_ expense: Expense) {
        modelContext.delete(expense)
        do {
            try modelContext.save()
            HapticManager.warning()
        } catch {
            print("Failed to delete expense from history: \(error)")
        }
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

    private struct ExpenseGroup: Identifiable {
        let title: String
        let items: [Expense]
        var id: String { title }
    }

    private enum GroupingMode: String, CaseIterable, Identifiable {
        case day
        case category
        case merchant

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "By Day"
            case .category: return "By Category"
            case .merchant: return "By Merchant"
            }
        }
    }

    private enum SortMode: String, CaseIterable, Identifiable {
        case newest
        case largest
        case alphabetical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newest: return "Newest"
            case .largest: return "Largest"
            case .alphabetical: return "A-Z"
            }
        }
    }

    private enum DateRangeFilter: String, CaseIterable, Identifiable {
        case month
        case last7Days
        case last30Days
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: return "Selected Month"
            case .last7Days: return "Last 7 Days"
            case .last30Days: return "Last 30 Days"
            case .custom: return "Custom"
            }
        }
    }
}
