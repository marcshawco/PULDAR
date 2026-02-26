import Foundation
import StoreKit

/// StoreKit 2 manager for the **$4.99 lifetime "Pro" unlock**.
///
/// - Loads the non-consumable product on launch.
/// - Checks existing entitlements (handles reinstalls / family sharing).
/// - Listens for background transaction updates.
@Observable
@MainActor
final class StoreKitManager {

    // MARK: - State

    private(set) var proProduct: Product?
    private(set) var isPro: Bool = UserDefaults.standard.bool(
        forKey: "didUnlockProLifetime"
    )
    private(set) var isLoading: Bool = false
    private(set) var purchaseError: String?
    private var didLoadProducts = false
    private var didCheckEntitlement = false

    // MARK: - Product Catalog

    private static let proProductID = AppConstants.proProductID

    // MARK: - Load Products

    func loadProducts(force: Bool = false) async {
        guard force || !didLoadProducts else { return }
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            didLoadProducts = true
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement Check

    /// Scans current entitlements — call on launch and after restoring purchases.
    func checkEntitlement(force: Bool = false) async {
        guard force || !didCheckEntitlement else { return }

        var foundEntitlement = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == Self.proProductID {
                foundEntitlement = true
                isPro = true
                UserDefaults.standard.set(true, forKey: "didUnlockProLifetime")
                didCheckEntitlement = true
                return
            }
        }

        // Keep cached "pro" state unless the user explicitly requests a forced
        // refresh (Restore Purchases), which should reflect the current source
        // of truth from StoreKit.
        if force && !foundEntitlement {
            isPro = false
            UserDefaults.standard.set(false, forKey: "didUnlockProLifetime")
        }
        didCheckEntitlement = true
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = proProduct else { return }
        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    isPro = true
                    UserDefaults.standard.set(true, forKey: "didUnlockProLifetime")
                    didCheckEntitlement = true
                    HapticManager.success()
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            HapticManager.warning()
        }

        isLoading = false
    }

    // MARK: - Transaction Listener

    /// Runs for the lifetime of the app to catch renewals / refunds / family sharing changes.
    func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let txn) = result {
                if txn.productID == Self.proProductID {
                    isPro = true
                    UserDefaults.standard.set(true, forKey: "didUnlockProLifetime")
                }
                await txn.finish()
            }
        }
    }
}
