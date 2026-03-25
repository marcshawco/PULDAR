//
//  ContentView.swift
//  PULDAR
//
//  Created by Marcus Shaw II on 2/22/26.
//

import SwiftUI
import SwiftData
import UIKit

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
    @State private var diagnosticLogger = DiagnosticLogger.shared
    @State private var financeKitManager = FinanceKitManager()
    @State private var appPreferences = AppPreferences()
    @State private var didWarmModelThisLaunch = false
    @AppStorage("didCompleteAppOnboarding") private var didCompleteAppOnboarding = false
    @AppStorage("appThemeMode") private var appThemeMode = "system"

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.secondarySystemBackground
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.18)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

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
        .environment(diagnosticLogger)
        .environment(financeKitManager)
        .environment(appPreferences)
        .overlay {
            WidgetSnapshotSyncView()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .preferredColorScheme(preferredColorScheme)
        .task(id: didCompleteAppOnboarding) {
            guard didCompleteAppOnboarding else { return }
            guard !didWarmModelThisLaunch else { return }
            didWarmModelThisLaunch = true
            Task.detached(priority: .utility) {
                await llmService.loadModel()
            }
        }
        .task {
            await storeKitManager.listenForTransactions()
        }
        .task {
            diagnosticLogger.record(
                category: "app.lifecycle",
                message: "App launched"
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { !didCompleteAppOnboarding },
                set: { if !$0 { didCompleteAppOnboarding = true } }
            )
        ) {
            AppOnboardingView {
                didCompleteAppOnboarding = true
            }
            .environment(llmService)
            .environment(networkMonitor)
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
