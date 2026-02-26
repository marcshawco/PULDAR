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
            Expense.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            if shouldRecoverByResetStore(from: error) {
                // Recover from known migration-validation failure (e.g. required field introduced).
                clearDefaultStoreFiles()

                do {
                    return try ModelContainer(for: schema, configurations: [configuration])
                } catch {
                    fatalError("Failed to create ModelContainer after store reset: \(error)")
                }
            }

            fatalError("Failed to create ModelContainer: \(error)")
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
}
