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
                return "$4.99/mo"
            case .yearly:
                return "$49.99/yr"
            }
        }

        var badge: String? {
            switch self {
            case .monthly:
                return "14 Days Free"
            case .yearly:
                return "14 Days Free + Save 17%"
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
            DiagnosticLogger.shared.record(
                category: "storekit.products",
                message: "Loaded subscription products",
                metadata: ["count": "\(proProducts.count)"]
            )
        } catch {
            purchaseError = Self.userVisibleErrorMessage(for: error)
            DiagnosticLogger.shared.record(
                level: .warning,
                category: "storekit.products",
                message: "Failed to load subscription products",
                metadata: ["error": error.localizedDescription]
            )
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
                DiagnosticLogger.shared.record(
                    category: "storekit.entitlement",
                    message: "Active entitlement detected",
                    metadata: ["productID": txn.productID]
                )
                return
            }
        }

        isPro = false
        activeProductID = nil
        UserDefaults.standard.set(false, forKey: "didUnlockProSubscription")
        didCheckEntitlement = true
        DiagnosticLogger.shared.record(
            category: "storekit.entitlement",
            message: "No active entitlement found"
        )
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
                    DiagnosticLogger.shared.record(
                        category: "storekit.purchase",
                        message: "Subscription purchase succeeded",
                        metadata: ["productID": txn.productID]
                    )
                    HapticManager.success()
                }
            case .userCancelled:
                DiagnosticLogger.shared.record(
                    category: "storekit.purchase",
                    message: "Subscription purchase cancelled by user",
                    metadata: ["plan": plan.rawValue]
                )
                break
            case .pending:
                DiagnosticLogger.shared.record(
                    category: "storekit.purchase",
                    message: "Subscription purchase pending",
                    metadata: ["plan": plan.rawValue]
                )
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = Self.userVisibleErrorMessage(for: error)
            DiagnosticLogger.shared.record(
                level: .warning,
                category: "storekit.purchase",
                message: "Subscription purchase failed",
                metadata: [
                    "plan": plan.rawValue,
                    "error": error.localizedDescription
                ]
            )
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
            DiagnosticLogger.shared.record(
                category: "storekit.restore",
                message: "Restore purchases completed"
            )
        } catch {
            purchaseError = Self.userVisibleErrorMessage(for: error)
            DiagnosticLogger.shared.record(
                level: .warning,
                category: "storekit.restore",
                message: "Restore purchases failed",
                metadata: ["error": error.localizedDescription]
            )
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
                    DiagnosticLogger.shared.record(
                        category: "storekit.transactions",
                        message: "Background transaction update received",
                        metadata: ["productID": txn.productID]
                    )
                }
                await txn.finish()
            } else {
                DiagnosticLogger.shared.record(
                    level: .warning,
                    category: "storekit.transactions",
                    message: "Transaction listener received unverified update"
                )
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

    private static func userVisibleErrorMessage(for error: Error) -> String? {
        let nsError = error as NSError
        guard !(nsError.domain == "ASDErrorDomain" && nsError.code == 509) else {
            return nil
        }
        return error.localizedDescription
    }
}
