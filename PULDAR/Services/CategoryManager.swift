import Foundation
import SwiftUI

/// User-customizable category names and custom category-to-bucket mappings.
@Observable
@MainActor
final class CategoryManager {
    struct CustomCategory: Identifiable, Codable, Hashable {
        var id: UUID
        var key: String
        var name: String
        var bucketRawValue: String

        var bucket: BudgetBucket {
            get { BudgetBucket(rawValue: bucketRawValue) ?? .fun }
            set { bucketRawValue = newValue.rawValue }
        }
    }

    struct ResolvedCategory {
        let storageKey: String
        let bucket: BudgetBucket
    }

    var renamedCategories: [String: String] {
        didSet { persistRenamedCategories() }
    }

    var customCategories: [CustomCategory] {
        didSet { persistCustomCategories() }
    }

    init() {
        renamedCategories = Self.loadRenamedCategories()
        customCategories = Self.loadCustomCategories()
    }

    var canonicalCategoryKeys: [String] {
        ExpenseCategory.allCases.map(\.rawValue)
    }

    /// User-visible name for a canonical category key.
    func displayName(forCanonicalKey key: String) -> String {
        if let renamed = renamedCategories[key], !renamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return renamed
        }
        return key.capitalized
    }

    /// User-visible name for a stored category key from an expense row.
    func displayName(forStoredCategory storedKey: String) -> String {
        let normalized = Self.normalize(storedKey)

        if canonicalCategoryKeys.contains(normalized) {
            return displayName(forCanonicalKey: normalized)
        }

        if let custom = customCategory(matching: normalized) {
            return custom.name
        }

        if let canonical = canonicalKey(forPromptLabel: normalized) {
            return displayName(forCanonicalKey: canonical)
        }

        return normalized.capitalized
    }

    /// Prompt-safe categories for the LLM (lowercased, deduplicated).
    var promptCategories: [String] {
        var result: [String] = []
        var seen: Set<String> = []

        func appendCategory(_ value: String) {
            let normalized = Self.normalize(value)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return }
            seen.insert(normalized)
            result.append(normalized)
        }

        for key in canonicalCategoryKeys {
            appendCategory(displayName(forCanonicalKey: key))
        }

        for custom in customCategories {
            appendCategory(custom.name)
        }

        if result.isEmpty {
            return canonicalCategoryKeys
        }

        return result
    }

    /// Resolve a raw LLM category output to storage key + bucket.
    ///
    /// `context` can include merchant and original user text so we can
    /// apply deterministic keyword overrides for obvious misclassifications.
    func resolve(raw: String, context: String? = nil) -> ResolvedCategory {
        let normalized = Self.normalize(raw)
        let normalizedContext = Self.normalize(context ?? "")
        let inferredFromContext = ExpenseCategory.keywordCategory(
            in: "\(normalized) \(normalizedContext)"
        )

        if let custom = customCategory(matching: normalized) {
            return ResolvedCategory(storageKey: custom.key, bucket: custom.bucket)
        }

        if let canonical = canonicalKey(forPromptLabel: normalized) {
            let canonicalCategory = ExpenseCategory.resolve(canonical)

            if let inferred = inferredFromContext,
               shouldOverride(canonical: canonicalCategory, with: inferred) {
                return ResolvedCategory(storageKey: inferred.rawValue, bucket: inferred.bucket)
            }

            return ResolvedCategory(
                storageKey: canonical,
                bucket: canonicalCategory.bucket
            )
        }

        if let inferred = inferredFromContext {
            return ResolvedCategory(storageKey: inferred.rawValue, bucket: inferred.bucket)
        }

        let fallback = ExpenseCategory.resolve(normalized)
        return ResolvedCategory(storageKey: fallback.rawValue, bucket: fallback.bucket)
    }

    private func shouldOverride(canonical: ExpenseCategory, with inferred: ExpenseCategory) -> Bool {
        if canonical == inferred { return false }
        if inferred == .investments { return true }

        // When the model chooses a strict "needs" category but context clearly
        // signals fun/travel/shopping, prefer the inferred fun-side category.
        if canonical.bucket == .fundamentals, inferred.bucket == .fun {
            return true
        }

        return false
    }

    func setDisplayName(_ name: String, forCanonicalKey key: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || Self.normalize(trimmed) == key {
            renamedCategories.removeValue(forKey: key)
        } else {
            renamedCategories[key] = trimmed
        }
    }

    @discardableResult
    func addCustomCategory(name: String, bucket: BudgetBucket) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.normalize(trimmed)
        guard !trimmed.isEmpty, !key.isEmpty else { return false }
        guard !canonicalCategoryKeys.contains(key) else { return false }
        guard !customCategories.contains(where: { $0.key == key }) else { return false }

        customCategories.append(
            CustomCategory(
                id: UUID(),
                key: key,
                name: trimmed,
                bucketRawValue: bucket.rawValue
            )
        )
        return true
    }

    func updateCustomCategory(id: UUID, name: String? = nil, bucket: BudgetBucket? = nil) {
        guard let index = customCategories.firstIndex(where: { $0.id == id }) else { return }
        var updated = customCategories[index]

        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                updated.name = trimmed
            }
        }

        if let bucket {
            updated.bucket = bucket
        }

        customCategories[index] = updated
    }

    func removeCustomCategories(at offsets: IndexSet) {
        customCategories.remove(atOffsets: offsets)
    }

    private func canonicalKey(forPromptLabel normalizedLabel: String) -> String? {
        if canonicalCategoryKeys.contains(normalizedLabel) {
            return normalizedLabel
        }

        for (key, label) in renamedCategories where Self.normalize(label) == normalizedLabel {
            return key
        }

        return nil
    }

    private func customCategory(matching normalizedLabel: String) -> CustomCategory? {
        customCategories.first {
            $0.key == normalizedLabel || Self.normalize($0.name) == normalizedLabel
        }
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static let renamedCategoriesKey = "renamedCategories"
    private static let customCategoriesKey = "customCategories"

    private static func loadRenamedCategories() -> [String: String] {
        if let data = UserDefaults.standard.data(forKey: renamedCategoriesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        return [:]
    }

    private static func loadCustomCategories() -> [CustomCategory] {
        if let data = UserDefaults.standard.data(forKey: customCategoriesKey),
           let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            return decoded
        }
        return []
    }

    private func persistRenamedCategories() {
        if let data = try? JSONEncoder().encode(renamedCategories) {
            UserDefaults.standard.set(data, forKey: Self.renamedCategoriesKey)
        }
    }

    private func persistCustomCategories() {
        if let data = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(data, forKey: Self.customCategoriesKey)
        }
    }
}
