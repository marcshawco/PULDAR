import SwiftUI
import SwiftData

struct WidgetSnapshotSyncView: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]
    @Query(sort: \RecurringExpense.createdAt, order: .reverse)
    private var recurringExpenses: [RecurringExpense]

    private var effectiveRecurringExpenses: [RecurringExpense] {
        storeKit.isPro ? recurringExpenses : []
    }

    private var statuses: [BudgetEngine.BucketStatus] {
        budgetEngine.calculateStatus(
            expenses: expenses,
            recurringExpenses: effectiveRecurringExpenses
        )
    }

    private var totalBudget: Double {
        statuses.reduce(0) { $0 + $1.budgeted }
    }

    private var totalSpent: Double {
        budgetEngine.totalSpent(
            expenses: expenses,
            recurringExpenses: effectiveRecurringExpenses
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                publishSnapshot()
            }
            .onChange(of: expenses.count) {
                publishSnapshot()
            }
            .onChange(of: recurringExpenses.count) {
                publishSnapshot()
            }
            .onChange(of: budgetEngine.monthlyIncome) {
                publishSnapshot()
            }
            .onChange(of: budgetEngine.rolloverEnabled) {
                publishSnapshot()
            }
            .onChange(of: budgetEngine.bucketPercentages) {
                publishSnapshot()
            }
            .onChange(of: storeKit.isPro) {
                publishSnapshot()
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                publishSnapshot()
            }
    }

    private func publishSnapshot() {
        WidgetBudgetSnapshotStore.publish(
            statuses: statuses,
            totalBudget: totalBudget,
            totalSpent: totalSpent
        )
    }
}
