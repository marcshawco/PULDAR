import Foundation
import StoreKit

/// StoreKit 2 manager for PULDAR Pro subscriptions.
///
/// - Loads monthly and yearly products on launch.
/// - Checks existing entitlements, including legacy lifetime unlocks.
/// - Listens for background transaction updates.
@Observable
@MainActor
final class StoreKitManager {

    enum ProPlan: String, CaseIterable, Identifiable {
        case monthly
        case yearly

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .monthly:
                return AppConstants.proMonthlyProductID
            case .yearly:
                return AppConstants.proYearlyProductID
            }
        }

        var marketingTitle: String {
            switch self {
            case .monthly:
                return "Monthly"
            case .yearly:
                return "Yearly"
            }
        }

        var marketingPrice: String {
            switch self {
            case .monthly:
                return "$2.99/mo"
            case .yearly:
                return "$25/yr"
            }
        }

        var badge: String? {
            switch self {
            case .monthly:
                return nil
            case .yearly:
                return "Best Value"
            }
        }
    }

    // MARK: - State

    private(set) var proProducts: [Product] = []
    private(set) var isPro: Bool = UserDefaults.standard.bool(
        forKey: "didUnlockProSubscription"
    )
    private(set) var isLoading: Bool = false
    private(set) var purchaseError: String?
    private(set) var activeProductID: String?
    private var didLoadProducts = false
    private var didCheckEntitlement = false

    // MARK: - Product Catalog

    private static let subscriptionProductIDs = [
        AppConstants.proMonthlyProductID,
        AppConstants.proYearlyProductID,
    ]
    private static let entitlementProductIDs = Set(
        subscriptionProductIDs + [AppConstants.legacyProLifetimeProductID]
    )

    // MARK: - Load Products

    func loadProducts(force: Bool = false) async {
        guard force || !didLoadProducts else { return }
        do {
            let products = try await Product.products(for: Self.subscriptionProductIDs)
            proProducts = products.sorted(by: Self.productSort)
            didLoadProducts = true
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement Check

    /// Scans current entitlements — call on launch and after restoring purchases.
    func checkEntitlement(force: Bool = false) async {
        guard force || !didCheckEntitlement else { return }

        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               Self.entitlementProductIDs.contains(txn.productID) {
                isPro = true
                activeProductID = txn.productID
                UserDefaults.standard.set(true, forKey: "didUnlockProSubscription")
                didCheckEntitlement = true
                return
            }
        }

        isPro = false
        activeProductID = nil
        UserDefaults.standard.set(false, forKey: "didUnlockProSubscription")
        didCheckEntitlement = true
    }

    // MARK: - Purchase

    func product(for plan: ProPlan) -> Product? {
        proProducts.first(where: { $0.id == plan.productID })
    }

    var defaultPlan: ProPlan {
        product(for: .yearly) == nil ? .monthly : .yearly
    }

    func purchase(plan: ProPlan) async {
        guard let product = product(for: plan) else { return }
        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    isPro = true
                    activeProductID = txn.productID
                    UserDefaults.standard.set(true, forKey: "didUnlockProSubscription")
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

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await checkEntitlement(force: true)
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
                if Self.entitlementProductIDs.contains(txn.productID) {
                    isPro = true
                    activeProductID = txn.productID
                    UserDefaults.standard.set(true, forKey: "didUnlockProSubscription")
                }
                await txn.finish()
            } else {
                await checkEntitlement(force: true)
            }
        }
    }

    private static func productSort(lhs: Product, rhs: Product) -> Bool {
        let lhsPriority = sortPriority(for: lhs.id)
        let rhsPriority = sortPriority(for: rhs.id)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.displayPrice < rhs.displayPrice
    }

    private static func sortPriority(for productID: String) -> Int {
        switch productID {
        case AppConstants.proYearlyProductID:
            return 0
        case AppConstants.proMonthlyProductID:
            return 1
        default:
            return 2
        }
    }
}
