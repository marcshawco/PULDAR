import SwiftUI
import SwiftData

/// Isolated input dock so keystrokes in the composer don't invalidate the
/// whole `FolioView` body. Mirrors `DashboardInputDock`.
private struct FolioInputDock: View {
    let isProcessing: Bool
    let onSubmit: (String) async -> Bool

    var body: some View {
        VStack(spacing: 8) {
            ExpenseInputView(
                isProcessing: isProcessing,
                onSubmit: onSubmit,
                placeholder: "added 250 to savings…"
            )
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            AppColors.secondaryBg
                .overlay(alignment: .top) {
                    AppColors.border.frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }
}

/// The Folio (net worth) screen — a balance sheet.
///
/// Layout (top-to-bottom): hero net-worth number → breakdown donut → three
/// collapsible groups (Assets, Funds, Liabilities) → AI composer dock.
/// Net Worth = Assets + Funds − Liabilities. Fully separate from the monthly
/// budget.
struct FolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FolioEngine.self) private var folioEngine
    @Environment(LLMService.self) private var llmService
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DiagnosticLogger.self) private var diagnosticLogger
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: \FolioItem.createdAt, order: .reverse) private var items: [FolioItem]
    @Query(sort: \FolioEntry.date, order: .reverse) private var entries: [FolioEntry]

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var editingItem: FolioItem?
    @State private var newItemKind: FolioKind?
    @State private var showHistory = false
    @State private var expandedKinds: Set<FolioKind> = [.asset, .fund, .liability]

    private let orderedKinds: [FolioKind] = [.asset, .fund, .liability]

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 900 : .infinity
    }

    private var netWorth: Double { folioEngine.netWorth(items: items) }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(AppColors.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Folio")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(orderedKinds) { kind in
                            Button {
                                newItemKind = kind
                            } label: {
                                Label("Add \(kind.singularName)", systemImage: kind.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .toolbarBackground(AppColors.secondaryBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FolioInputDock(
                    isProcessing: isProcessing,
                    onSubmit: { text in await submitFolioCommand(text) }
                )
            }
            .sheet(item: $editingItem) { item in
                FolioItemEditSheet(existingItem: item, initialKind: item.itemKind)
                    .environment(folioEngine)
                    .environment(appPreferences)
            }
            .sheet(item: $newItemKind) { kind in
                FolioItemEditSheet(existingItem: nil, initialKind: kind)
                    .environment(folioEngine)
                    .environment(appPreferences)
            }
            .sheet(isPresented: $showHistory) {
                FolioHistoryView()
                    .environment(appPreferences)
                    .environment(diagnosticLogger)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            modelStatusBanner

            if showError, let msg = errorMessage {
                errorBanner(msg)
            }

            FolioHeroView(
                netWorth: netWorth,
                assetsTotal: folioEngine.total(for: .asset, items: items),
                fundsTotal: folioEngine.total(for: .fund, items: items),
                liabilitiesTotal: folioEngine.total(for: .liability, items: items)
            )

            Divider()

            if items.isEmpty {
                FolioEmptyStateView()
            } else {
                let slices = folioEngine.allocationSlices(items: items)
                if !slices.isEmpty {
                    FolioBreakdownChart(slices: slices, netWorth: netWorth)
                        .padding(.vertical, 12)
                    Divider()
                }

                ForEach(orderedKinds) { kind in
                    FolioGroupSection(
                        kind: kind,
                        total: folioEngine.total(for: kind, items: items),
                        items: folioEngine.items(of: kind, in: items),
                        isExpanded: expandedKinds.contains(kind),
                        onToggle: { toggle(kind) },
                        onSelectItem: { editingItem = $0 },
                        onAddItem: { newItemKind = kind }
                    )
                    Divider()
                }
            }

            Spacer(minLength: 140)
        }
    }

    private func toggle(_ kind: FolioKind) {
        HapticManager.light()
        withAnimation(.easeInOut(duration: 0.22)) {
            if expandedKinds.contains(kind) {
                expandedKinds.remove(kind)
            } else {
                expandedKinds.insert(kind)
            }
        }
    }

    // MARK: - Submit

    private func submitFolioCommand(_ rawInput: String) async -> Bool {
        guard !rawInput.isEmpty else { return false }
        diagnosticLogger.record(
            category: "folio.submit",
            message: "Started Folio parsing",
            metadata: ["inputLength": "\(rawInput.count)"]
        )
        isProcessing = true
        showError = false
        errorMessage = nil

        do {
            let command = try await llmService.parseFolioCommand(
                from: rawInput,
                currencyCode: appPreferences.currencyCode,
                inputLanguage: appPreferences.inputLanguage
            )
            let result = folioEngine.apply(
                command: command,
                to: items,
                in: modelContext,
                originalInput: rawInput
            )

            switch result {
            case .created, .updated:
                HapticManager.success()
                isProcessing = false
                return true
            case .failed(let reason):
                presentTransientError(reason)
                HapticManager.warning()
                isProcessing = false
                return false
            }
        } catch {
            presentTransientError(error.localizedDescription)
            HapticManager.warning()
            isProcessing = false
            return false
        }
    }

    private func presentTransientError(_ message: String) {
        errorMessage = message
        withAnimation { showError = true }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation { showError = false }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var modelStatusBanner: some View {
        switch llmService.loadState {
        case .downloading(let progress):
            let safeProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
            if safeProgress < 0.995 {
                HStack(spacing: 8) {
                    ProgressView(value: safeProgress)
                        .tint(AppColors.accent)
                    Text("Downloading AI model… \(Int(safeProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.secondaryBg)
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .thin))
                Text(msg)
                    .font(.caption2)
            }
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal)
            .padding(.top, 8)
        default:
            EmptyView()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .thin))
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(AppColors.overspend)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.overspend.opacity(0.08))
        )
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
