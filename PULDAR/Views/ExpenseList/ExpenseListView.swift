import SwiftUI
import SwiftData

/// Progressively-disclosed list of recent expense logs.
///
/// Filters in real time when `searchText` is non-empty and
/// delegates yellow highlighting down to each row.
struct ExpenseListView: View {
    @Environment(CategoryManager.self) private var categoryManager
    let expenses: [Expense]
    let searchText: String
    let onDeleteExpense: (Expense) -> Void

    /// Show 10 items initially, load more on scroll.
    @State private var visibleCount = 10
    @State private var debouncedSearchText = ""
    @State private var debounceTask: Task<Void, Never>?

    private var filteredExpenses: [Expense] {
        guard !debouncedSearchText.isEmpty else { return expenses }
        let query = debouncedSearchText.lowercased()
        return expenses.filter {
            let categoryDisplay = categoryManager
                .displayName(forStoredCategory: $0.category)
                .lowercased()
            return $0.normalizedMerchant.lowercased().contains(query)
                || $0.category.lowercased().contains(query)
                || categoryDisplay.contains(query)
                || $0.notes.lowercased().contains(query)
                || $0.budgetBucket.rawValue.lowercased().contains(query)
                || ($0.isOverspent && "overspent".contains(query))
        }
    }

    private var visibleExpenses: [Expense] {
        Array(filteredExpenses.prefix(visibleCount))
    }

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(visibleExpenses) { expense in
                SwipeToDeleteExpenseRow(
                    expense: expense,
                    highlightText: searchText,
                    onDelete: { onDeleteExpense(expense) }
                )
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
        }
        .onChange(of: searchText) {
            visibleCount = 10   // Reset pagination on new search
            debounceTask?.cancel()

            let pending = searchText
            if pending.isEmpty {
                debouncedSearchText = ""
                return
            }

            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    debouncedSearchText = pending
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }
}

private struct SwipeToDeleteExpenseRow: View {
    let expense: Expense
    let highlightText: String
    let onDelete: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var isRevealed = false

    private let revealWidth: CGFloat = 88
    private let fullDeleteThreshold: CGFloat = 140
    private let maxDragWidth: CGFloat = 180

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.overspend)

            Button(role: .destructive) {
                settleSwipe(to: -revealWidth)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onDelete()
                }
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
            }
            .buttonStyle(.plain)
            .opacity(isRevealed || offsetX < -20 ? 1 : 0)

            ExpenseRowView(
                expense: expense,
                highlightText: highlightText
            )
            .offset(x: offsetX)
            .highPriorityGesture(dragGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let base = isRevealed ? -revealWidth : 0
                let proposed = base + value.translation.width
                offsetX = min(0, max(-maxDragWidth, proposed))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    settleSwipe(to: isRevealed ? -revealWidth : 0)
                    return
                }

                let projected = offsetX + (value.predictedEndTranslation.width - value.translation.width)
                if projected < -fullDeleteThreshold {
                    settleSwipe(to: -revealWidth)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDelete()
                    }
                    return
                }

                if projected < -(revealWidth * 0.5) {
                    isRevealed = true
                    settleSwipe(to: -revealWidth)
                } else {
                    isRevealed = false
                    settleSwipe(to: 0)
                }
            }
    }

    private func settleSwipe(to value: CGFloat) {
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
            offsetX = value
        }
    }
}
