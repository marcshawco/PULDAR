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
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Expense.self,
            RecurringExpense.self
        ])

        do {
            return try makeModelContainer(schema: schema, cloudSyncEnabled: true)
        } catch {
            if shouldRecoverByResetStore(from: error) {
                // Recover from known migration-validation failure (e.g. required field introduced).
                clearDefaultStoreFiles()

                do {
                    return try makeModelContainer(schema: schema, cloudSyncEnabled: true)
                } catch {
                    do {
                        return try makeModelContainer(schema: schema, cloudSyncEnabled: false)
                    } catch {
                        fatalError("Failed to create ModelContainer after store reset: \(error)")
                    }
                }
            }

            do {
                return try makeModelContainer(schema: schema, cloudSyncEnabled: false)
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

    private static func clearDefaultStoreFiles() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let knownNames = [
            "default.store",
            "default.store-shm",
            "default.store-wal",
        ]

        for name in knownNames {
            let url = appSupport.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func shouldRecoverByResetStore(from error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 134110 {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSCocoaErrorDomain,
           underlying.code == 134110 {
            return true
        }

        return false
    }

    private static func makeModelContainer(
        schema: Schema,
        cloudSyncEnabled: Bool
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if cloudSyncEnabled {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
