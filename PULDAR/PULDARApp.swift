//
//  PULDARApp.swift
//  PULDAR
//
//  Created by Marcus Shaw II on 2/22/26.
//

import SwiftUI
import SwiftData

@main
struct PULDARApp: App {
    private enum StoreConfigurationError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "The app group container is unavailable."
            }
        }
    }

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Expense.self,
            RecurringExpense.self
        ])

        do {
            return try makeCloudModelContainer(schema: schema)
        } catch {
            // Recover from known migration-validation failures by resetting the stores.
            if shouldRecoverByResetStore(from: error) {
                clearKnownStoreFiles()

                do {
                    return try makeCloudModelContainer(schema: schema)
                } catch {
                    do {
                        return try makeLocalModelContainer(schema: schema)
                    } catch {
                        fatalError("Failed to create ModelContainer after store reset: \(error)")
                    }
                }
            }

            do {
                return try makeLocalModelContainer(schema: schema)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.sharedModelContainer)
    }

    private static func clearKnownStoreFiles() {
        let fm = FileManager.default
        for url in knownStoreURLs() where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    private static func knownStoreURLs() -> [URL] {
        let urls = [localStoreURL(), cloudStoreURL()].compactMap { $0 }

        return urls.flatMap { url in
            [
                url,
                url.appendingPathExtension("shm"),
                url.appendingPathExtension("wal"),
            ]
        }
    }

    private static func localStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory

        let directory = appSupport.appendingPathComponent("PULDAR", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("local.store")
    }

    private static func cloudStoreURL() -> URL? {
        let fm = FileManager.default
        guard let appGroupRoot = fm.containerURL(
            forSecurityApplicationGroupIdentifier: "group.marcshaw.PULDAR"
        ) else {
            return nil
        }

        let directory = appGroupRoot
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("PULDARCloudStore.store")
    }

    private static func shouldRecoverByResetStore(from error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, [134110, 134060].contains(nsError.code) {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSCocoaErrorDomain,
           [134110, 134060].contains(underlying.code) {
            return true
        }

        return false
    }

    private static func makeCloudModelContainer(schema: Schema) throws -> ModelContainer {
        guard cloudStoreURL() != nil else {
            throw StoreConfigurationError.appGroupUnavailable
        }

        let configuration = ModelConfiguration(
            "PULDARCloudStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier("group.marcshaw.PULDAR"),
            cloudKitDatabase: .automatic
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeLocalModelContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "PULDARLocalStore",
            schema: schema,
            url: localStoreURL(),
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
