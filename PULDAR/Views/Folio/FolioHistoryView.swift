import SwiftUI
import SwiftData

/// The Folio ledger — every dated change to net worth, with CSV / JSON export.
struct FolioHistoryView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DiagnosticLogger.self) private var diagnosticLogger
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \FolioEntry.date, order: .reverse) private var entries: [FolioEntry]
    @Query(sort: \FolioItem.createdAt, order: .reverse) private var items: [FolioItem]

    @State private var exportURL: URL?
    @State private var showExportSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if entries.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().padding(.leading, 20)
                            }
                            entryRow(entry)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .background(AppColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Ledger")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.textTertiary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExportSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty && items.isEmpty)
                }
            }
            .toolbarBackground(AppColors.secondaryBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showExportSheet) {
                exportSheet
            }
        }
    }

    // MARK: - Rows

    private func entryRow(_ entry: FolioEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.itemName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(subtitle(for: entry))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(deltaText(for: entry))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.signedDelta >= 0 ? AppColors.success : AppColors.overspend)
                    .monospacedDigit()

                Text("→ \(entry.resultingValue.formattedCurrency(code: appPreferences.currencyCode))")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func subtitle(for entry: FolioEntry) -> String {
        let date = entry.date.formatted(date: .abbreviated, time: .omitted)
        if entry.folioOperation == .percentChange, let percent = entry.percent {
            let sign = percent >= 0 ? "+" : ""
            return "\(entry.folioOperation.displayName) \(sign)\(percent.formatted(.number.precision(.fractionLength(0...2))))% · \(date)"
        }
        return "\(entry.folioOperation.displayName) · \(date)"
    }

    private func deltaText(for entry: FolioEntry) -> String {
        let magnitude = abs(entry.delta).formattedCurrency(code: appPreferences.currencyCode)
        return (entry.delta >= 0 ? "+" : "−") + magnitude
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No changes yet")
                .font(.headline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
            Text("Updates to your items will show up here.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 20)
    }

    // MARK: - Export

    private var exportSheet: some View {
        NavigationStack {
            List {
                Section("Export") {
                    Button("Ledger (CSV)") {
                        runExport { try FolioExportService.writeLedgerCSV(entries: entries) }
                    }
                    Button("Items (CSV)") {
                        runExport { try FolioExportService.writeItemsCSV(items: items) }
                    }
                    Button("Full Backup (JSON)") {
                        runExport { try FolioExportService.writeFolioJSON(items: items, entries: entries) }
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Last Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showExportSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func runExport(_ build: () throws -> URL) {
        do {
            exportURL = try build()
            diagnosticLogger.record(
                category: "folio.export",
                message: "Exported Folio data",
                metadata: ["items": "\(items.count)", "entries": "\(entries.count)"]
            )
        } catch {
            diagnosticLogger.record(
                level: .error,
                category: "folio.export",
                message: "Failed Folio export",
                metadata: ["error": error.localizedDescription]
            )
        }
    }
}
