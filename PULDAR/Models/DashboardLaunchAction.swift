import Foundation

struct DashboardLaunchAction: Identifiable, Equatable {
    enum Kind: String {
        case focusComposer
        case scanReceipt
    }

    let id = UUID()
    let kind: Kind
}
