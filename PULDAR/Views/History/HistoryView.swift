import SwiftUI
import SwiftData

/// Historical reporting by month with CSV export.
struct HistoryView: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(CategoryManager.self) private var categoryManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var selectedMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var exportURL: URL?

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

    private var selectedStatuses: [BudgetEngine.BucketStatus] {
        budgetEngine.calculateStatus(expenses: selectedMonthExpenses, for: selectedMonth)
    }

    private var selectedTotal: Double {
        selectedMonthExpenses.reduce(0) { $0 + $1.amount }
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
                    Button("Export Selected Month (CSV)") {
                        exportCSV(for: selectedMonthExpenses, scope: monthLabel(selectedMonth))
                    }
                    Button("Export All Data (CSV)") {
                        exportCSV(for: expenses, scope: "all_months")
                    }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Last Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Entries") {
                    if selectedMonthExpenses.isEmpty {
                        Text("No entries for this month.")
                            .foregroundStyle(AppColors.textTertiary)
                    } else {
                        ForEach(selectedMonthExpenses) { expense in
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
                    }
                }
            }
            .navigationTitle("History")
            .onAppear {
                if let first = monthOptions.first {
                    selectedMonth = first
                }
            }
        }
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide))
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
}
