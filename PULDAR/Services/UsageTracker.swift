import Foundation

/// Legacy placeholder retained now that entries are unlimited for everyone.
@Observable
final class UsageTracker {
    var currentCount: Int { 0 }

    func recordInput() {}
    func reconcile(with expenses: [Expense]) {}
}
