import SwiftUI
import SwiftData

/// Settings sheet — income setup and bucket preview.
struct SettingsView: View {
    @Environment(BudgetEngine.self) private var budgetEngine
    @Environment(StoreKitManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allExpenses: [Expense]

    @State private var incomeText: String = ""
    @FocusState private var isIncomeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // ── Income Section ─────────────────────────────────────
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(AppColors.textTertiary)
                        TextField("Monthly income", text: $incomeText)
                            .keyboardType(.decimalPad)
                            .focused($isIncomeFocused)
                            .onChange(of: incomeText) {
                                if let value = Double(incomeText) {
                                    budgetEngine.monthlyIncome = value
                                }
                            }
                    }
                } header: {
                    Text("Monthly Income")
                } footer: {
                    Text("Your income is stored locally and never leaves this device.")
                }

                // ── Bucket Breakdown ───────────────────────────────────
                if budgetEngine.monthlyIncome > 0 {
                    Section("Budget Breakdown") {
                        ForEach(BudgetBucket.allCases) { bucket in
                            HStack(spacing: 10) {
                                Image(systemName: bucket.icon)
                                    .font(.system(size: 12, weight: .thin))
                                    .foregroundStyle(bucket.color)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(bucket.rawValue)
                                        .font(.subheadline.weight(.medium))
                                    Text(bucket.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textTertiary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(
                                        budgetEngine.bucketBudget(for: bucket),
                                        format: .currency(code: "USD")
                                    )
                                    .font(.subheadline.weight(.medium))

                                    Text("\(Int(bucket.targetPercentage * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // ── Pro Status ─────────────────────────────────────────
                Section("Account") {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(store.isPro ? "Pro (Lifetime)" : "Free")
                            .foregroundStyle(
                                store.isPro ? .green : AppColors.textSecondary
                            )
                    }

                    if !store.isPro {
                        Button("Restore Purchases") {
                            Task { await store.checkEntitlement() }
                        }
                    }
                }

                // ── Danger Zone ────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        clearAllExpenses()
                    } label: {
                        Label("Delete All Expenses", systemImage: "trash")
                            .font(.subheadline)
                    }
                } footer: {
                    Text("This action cannot be undone.")
                }

                // ── About ──────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("AI Model", value: "Qwen 2.5 0.5B")
                    LabeledContent("Processing", value: "100% On-Device")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
            .onAppear {
                if budgetEngine.monthlyIncome > 0 {
                    incomeText = String(format: "%.0f", budgetEngine.monthlyIncome)
                }
            }
        }
    }

    // MARK: - Data Operations

    private func clearAllExpenses() {
        do {
            try modelContext.delete(model: Expense.self)
            HapticManager.warning()
        } catch {
            print("Failed to delete expenses: \(error)")
        }
    }
}
