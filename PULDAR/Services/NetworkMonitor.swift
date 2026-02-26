import Foundation
import Network
import SwiftUI

/// Lightweight monitor used for onboarding download decisions.
@Observable
@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PULDAR.NetworkMonitor")

    var isConnected = true
    var isOnWiFi = false
    var isUsingCellular = false
    var isExpensive = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in self.apply(path: path) }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var connectionLabel: String {
        if !isConnected { return "No internet connection" }
        if isOnWiFi { return "Connected on Wi-Fi" }
        if isUsingCellular || isExpensive { return "Connected on cellular data" }
        return "Connected network"
    }

    private func apply(path: NWPath) {
        isConnected = (path.status == .satisfied)
        isOnWiFi = path.usesInterfaceType(.wifi)
        isUsingCellular = path.usesInterfaceType(.cellular)
        isExpensive = path.isExpensive
    }
}
