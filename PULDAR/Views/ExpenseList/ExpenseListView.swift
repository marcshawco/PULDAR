import SwiftUI
import SwiftData

/// Progressively-disclosed list of recent expense logs.
///
/// Filters in real time when `searchText` is non-empty and
/// delegates yellow highlighting down to each row.
struct ExpenseListView: View {
    let expenses: [Expense]
    let searchText: String

    /// Show 10 items initially, load more on scroll.
    @State private var visibleCount = 10

    private var filteredExpenses: [Expense] {
        guard !searchText.isEmpty else { return expenses }
        let query = searchText.lowercased()
        return expenses.filter {
            $0.merchant.lowercased().contains(query)
            || $0.category.lowercased().contains(query)
            || $0.notes.lowercased().contains(query)
            || $0.budgetBucket.rawValue.lowercased().contains(query)
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
                    highlightText: searchText
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
        .animation(.spring(duration: 0.4), value: filteredExpenses.count)
        .onChange(of: searchText) {
            visibleCount = 10   // Reset pagination on new search
        }
    }
}
