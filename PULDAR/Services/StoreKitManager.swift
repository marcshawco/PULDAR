import Foundation

/// Legacy placeholder retained so older environment wiring can be reintroduced
/// without bringing back purchase logic.
@Observable
@MainActor
final class StoreKitManager {
    private(set) var isPro: Bool = true

    func loadProducts(force: Bool = false) async {}

    func checkEntitlement(force: Bool = false) async {}

    func listenForTransactions() async {}
}
