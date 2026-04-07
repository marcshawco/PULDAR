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
    private enum RootTab: Hashable {
        case home
        case history
    }

    // MARK: - Services (owned at the root)

    @State private var llmService = LLMService()
    @State private var budgetEngine = BudgetEngine()
    @State private var categoryManager = CategoryManager()
    @State private var networkMonitor = NetworkMonitor()
    @State private var diagnosticLogger = DiagnosticLogger.shared
    @State private var financeKitManager = FinanceKitManager()
    @State private var appPreferences = AppPreferences()
    @State private var didWarmModelThisLaunch = false
    @State private var selectedTab: RootTab = .home
    @State private var dashboardLaunchAction: DashboardLaunchAction?
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
        TabView(selection: $selectedTab) {
            DashboardView(launchAction: $dashboardLaunchAction)
                .environment(llmService)
                .environment(appPreferences)
                .environment(budgetEngine)
                .environment(categoryManager)
                .environment(diagnosticLogger)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RootTab.home)

            HistoryView()
                .environment(appPreferences)
                .environment(budgetEngine)
                .environment(categoryManager)
                .environment(diagnosticLogger)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(RootTab.history)
        }
        .environment(llmService)
        .environment(budgetEngine)
        .environment(categoryManager)
        .environment(networkMonitor)
        .environment(diagnosticLogger)
        .environment(financeKitManager)
        .environment(appPreferences)
        .overlay {
            WidgetSnapshotSyncView()
                .environment(budgetEngine)
                .environment(appPreferences)
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
            .environment(appPreferences)
            .environment(budgetEngine)
            .environment(categoryManager)
            .environment(diagnosticLogger)
            .environment(financeKitManager)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
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

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "puldar" else { return }

        selectedTab = .home

        switch url.host?.lowercased() {
        case "quick-add":
            dashboardLaunchAction = DashboardLaunchAction(kind: .focusComposer)
        case "scan-receipt":
            dashboardLaunchAction = DashboardLaunchAction(kind: .scanReceipt)
        default:
            break
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Expense.self, RecurringExpense.self], inMemory: true)
}
