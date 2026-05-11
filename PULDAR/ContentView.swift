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
        case settings
    }

    // MARK: - Services (owned at the root)

    @State private var llmService = LLMService()
    @State private var budgetEngine = BudgetEngine()
    @State private var categoryManager = CategoryManager()
    @State private var networkMonitor = NetworkMonitor()
    @State private var usageTracker = UsageTracker()
    @State private var diagnosticLogger = DiagnosticLogger.shared
    @State private var appPreferences = AppPreferences()
    @State private var selectedTab: RootTab = .home
    @State private var dashboardLaunchAction: DashboardLaunchAction?
    @State private var showAppOnboarding = false
    @AppStorage("didCompleteAppOnboarding") private var didCompleteAppOnboarding = false
    @AppStorage("appThemeMode") private var appThemeMode = "system"

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "surface") ?? UIColor.systemBackground
        appearance.shadowColor = UIColor(named: "border")?.withAlphaComponent(0.5) ?? UIColor.separator.withAlphaComponent(0.12)

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor(named: "text3") ?? UIColor.tertiaryLabel,
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(named: "text1") ?? UIColor.label,
        ]

        for state in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            state.normal.titleTextAttributes = normalAttrs
            state.selected.titleTextAttributes = selectedAttrs
            state.normal.iconColor = UIColor(named: "text3") ?? UIColor.tertiaryLabel
            state.selected.iconColor = UIColor(named: "text1") ?? UIColor.label
        }

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
                .environment(usageTracker)
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
                    Label("History", systemImage: "calendar")
                }
                .tag(RootTab.history)

            SettingsView {
                showAppOnboarding = true
            }
                .environment(appPreferences)
                .environment(budgetEngine)
                .environment(categoryManager)
                .environment(usageTracker)
                .environment(diagnosticLogger)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .environment(llmService)
        .environment(budgetEngine)
        .environment(categoryManager)
        .environment(networkMonitor)
        .environment(usageTracker)
        .environment(diagnosticLogger)
        .environment(appPreferences)
        .overlay {
            WidgetSnapshotSyncView()
                .environment(budgetEngine)
                .environment(appPreferences)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .preferredColorScheme(preferredColorScheme)
        .task {
            diagnosticLogger.record(
                category: "app.lifecycle",
                message: "App launched"
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { showAppOnboarding || !didCompleteAppOnboarding },
                set: { isPresented in
                    guard !isPresented else { return }
                    showAppOnboarding = false
                    didCompleteAppOnboarding = true
                }
            )
        ) {
            AppOnboardingView {
                showAppOnboarding = false
                didCompleteAppOnboarding = true
            }
            .environment(llmService)
            .environment(networkMonitor)
            .environment(appPreferences)
            .environment(budgetEngine)
            .environment(categoryManager)
            .environment(diagnosticLogger)
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
