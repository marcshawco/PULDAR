//
//  ContentView.swift
//  PULDAR
//
//  Created by Marcus Shaw II on 2/22/26.
//

import SwiftUI

/// Root coordinator that owns all service objects and injects them
/// into the environment for the entire view hierarchy.
struct ContentView: View {

    // MARK: - Services (owned at the root)

    @State private var llmService = LLMService()
    @State private var budgetEngine = BudgetEngine()
    @State private var storeKitManager = StoreKitManager()
    @State private var usageTracker = UsageTracker()

    // MARK: - Body

    var body: some View {
        DashboardView()
            .environment(llmService)
            .environment(budgetEngine)
            .environment(storeKitManager)
            .environment(usageTracker)
            .task {
                // Long-lived transaction listener — runs for the app's lifetime.
                await storeKitManager.listenForTransactions()
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Expense.self, inMemory: true)
}
