import SwiftUI
import SwiftData

/// Add or edit a single Folio item. Manual valuation only — no network.
///
/// Saving routes through `FolioEngine.upsertItem`, which records a ledger
/// entry so the trend and history stay consistent.
struct FolioItemEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FolioEngine.self) private var folioEngine
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.dismiss) private var dismiss

    private let existingItem: FolioItem?

    @State private var name: String
    @State private var kind: FolioKind
    @State private var category: FolioCategory
    @State private var amountText: String
    @State private var notes: String

    init(existingItem: FolioItem?, initialKind: FolioKind) {
        self.existingItem = existingItem
        let resolvedKind = existingItem?.itemKind ?? initialKind
        _name = State(initialValue: existingItem?.name ?? "")
        _kind = State(initialValue: resolvedKind)
        _category = State(
            initialValue: existingItem?.folioCategory
                ?? FolioCategory.categories(for: resolvedKind).first
                ?? .other
        )
        _amountText = State(
            initialValue: existingItem.map { String(format: "%.2f", $0.currentValue) } ?? ""
        )
        _notes = State(initialValue: existingItem?.notes ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColors.border)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameField
                    kindSelector
                    categoryField
                    valueField
                    notesField
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            if existingItem != nil {
                deleteButton
            }
        }
        .background(AppColors.secondaryBg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onChange(of: kind) { _, newKind in
            if category.kind != newKind {
                category = FolioCategory.categories(for: newKind).first ?? .other
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)

            Spacer()

            Text(existingItem == nil ? "Add \(kind.singularName)" : "Edit \(kind.singularName)")
                .font(.system(size: 13, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button("Save") { save() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canSave ? AppColors.textPrimary : AppColors.textTertiary)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("Name")
            TextField(category.displayName, text: $name)
                .font(.system(size: 17))
                .foregroundStyle(AppColors.textPrimary)
                .textInputAutocapitalization(.words)
            Divider()
        }
    }

    private var kindSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Type")
            HStack(spacing: 8) {
                ForEach([FolioKind.asset, .fund, .liability]) { option in
                    Button {
                        kind = option
                    } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 7, height: 7)
                            Text(option.singularName.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .kerning(0.6)
                                .foregroundStyle(kind == option ? option.color : AppColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(kind == option ? option.color.opacity(0.08) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(kind == option ? option.color : AppColors.border, lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("Category")
            Menu {
                ForEach(FolioCategory.categories(for: kind), id: \.self) { option in
                    Button(option.displayName) { category = option }
                }
            } label: {
                HStack {
                    Text(category.displayName)
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Divider()
        }
    }

    private var valueField: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(kind == .liability ? "Balance Owed" : "Current Value")
            HStack {
                Text(appPreferences.currencyPreference.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textTertiary)
                TextField("0.00", text: $amountText)
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textPrimary)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
            }
            Divider()
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("Notes")
            TextField("Optional", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1...3)
            Divider()
        }
    }

    private var deleteButton: some View {
        Button {
            if let existingItem {
                folioEngine.deleteItem(existingItem, in: modelContext)
                HapticManager.warning()
                dismiss()
            }
        } label: {
            Text("Delete \(kind.singularName)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.overspend)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.overspend.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.overspend.opacity(0.19), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .kerning(1.2)
            .textCase(.uppercase)
            .foregroundStyle(AppColors.textTertiary)
    }

    // MARK: - Save

    private var parsedValue: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || parsedValue > 0
    }

    private func save() {
        folioEngine.upsertItem(
            existing: existingItem,
            name: name,
            kind: kind,
            category: category,
            value: parsedValue,
            notes: notes,
            in: modelContext
        )
        HapticManager.success()
        dismiss()
    }
}
