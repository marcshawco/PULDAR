//
//  ContentView.swift
//  PULDAR
//
//  Created by Marcus Shaw II on 2/22/26.
//

import SwiftUI
import SwiftData

/// Root coordinator that owns all service objects and injects them
/// into the environment for the entire view hierarchy.
struct ContentView: View {

    // MARK: - Services (owned at the root)

    @State private var llmService = LLMService()
    @State private var budgetEngine = BudgetEngine()
    @State private var categoryManager = CategoryManager()
    @State private var networkMonitor = NetworkMonitor()
    @State private var storeKitManager = StoreKitManager()
    @State private var usageTracker = UsageTracker()
    @State private var didWarmModelThisLaunch = false
    @AppStorage("appThemeMode") private var appThemeMode = "system"

    // MARK: - Body

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .environment(llmService)
        .environment(budgetEngine)
        .environment(categoryManager)
        .environment(networkMonitor)
        .environment(storeKitManager)
        .environment(usageTracker)
        .preferredColorScheme(preferredColorScheme)
        .task {
            guard !didWarmModelThisLaunch else { return }
            didWarmModelThisLaunch = true
            Task.detached(priority: .utility) {
                await llmService.loadModel()
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appThemeMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Expense.self, RecurringExpense.self], inMemory: true)
}
