import Foundation
import Observation
import UIKit

/// Optional, privacy-friendly local diagnostics for support investigations.
///
/// Logs never leave the device unless the user explicitly exports them.
@Observable
@MainActor
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    enum Level: String, Codable {
        case info
        case warning
        case error
    }

    struct Entry: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        let metadata: [String: String]
    }

    struct ExportBundle: Codable {
        struct AppInfo: Codable {
            let appVersion: String
            let buildNumber: String
            let systemVersion: String
            let deviceModel: String
            let generatedAt: Date
        }

        let app: AppInfo
        let diagnosticsEnabled: Bool
        let entryCount: Int
        let entries: [Entry]
        let state: SupportState
    }

    struct SupportState: Codable {
        struct BucketState: Codable {
            let name: String
            let budgeted: Double
            let spent: Double
            let remaining: Double
            let isOverspent: Bool
        }

        let monthlyIncome: Double
        let rolloverEnabled: Bool
        let percentages: [String: Double]
        let expenseCount: Int
        let recurringExpenseCount: Int
        let filteredMonth: String
        let monthSpent: Double
        let monthCapacity: Double
        let buckets: [BucketState]
    }

    private enum StorageKey {
        static let enabled = "diagnosticLoggingEnabled"
    }

    private let defaults = UserDefaults.standard
    private let maxEntries = 400

    private(set) var isEnabled: Bool
    private(set) var entries: [Entry] = []

    private init() {
        isEnabled = defaults.bool(forKey: StorageKey.enabled)
        entries = loadEntries()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: StorageKey.enabled)
        if enabled {
            record(category: "diagnostics", message: "User enabled local diagnostic logging")
        }
    }

    func record(
        level: Level = .info,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled else { return }

        let entry = Entry(
            id: UUID(),
            timestamp: .now,
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )

        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persistEntries()
    }

    func clear() {
        entries.removeAll(keepingCapacity: false)
        let fm = FileManager.default
        let url = storageURL()
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    func export(state: SupportState) throws -> URL {
        let bundle = ExportBundle(
            app: ExportBundle.AppInfo(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
                systemVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
                generatedAt: .now
            ),
            diagnosticsEnabled: isEnabled,
            entryCount: entries.count,
            entries: entries,
            state: state
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("puldar_diagnostics_\(Int(Date.now.timeIntervalSince1970)).json")
        let data = try encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func loadEntries() -> [Entry] {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }

        let url = storageURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func storageURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return appSupport
            .appendingPathComponent("PULDAR", isDirectory: true)
            .appendingPathComponent("diagnostic_logs.json")
    }
}
