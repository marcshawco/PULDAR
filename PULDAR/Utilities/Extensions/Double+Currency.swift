import Foundation

extension Double {
    func formattedCurrency(code: String) -> String {
        formatted(.currency(code: code))
    }
}
