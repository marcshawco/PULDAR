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
    private(set) var isPro: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var purchaseError: String?

    // MARK: - Product Catalog

    private static let proProductID = AppConstants.proProductID

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement Check

    /// Scans current entitlements — call on launch and after restoring purchases.
    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == Self.proProductID {
                isPro = true
                return
            }
        }
        isPro = false
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
                }
                await txn.finish()
            }
        }
    }
}
