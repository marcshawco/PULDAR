import Foundation

extension Double {
    func formattedCurrency(code: String) -> String {
        let safe = isFinite ? self : 0
        return CurrencyFormatterCache.formatter(for: code).string(from: NSNumber(value: safe))
            ?? "\(safe)"
    }
}

/// `NumberFormatter` is expensive to construct (locale lookup, symbol decoration).
/// Cache one per currency code so per-row formatting is a dictionary lookup.
private enum CurrencyFormatterCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NumberFormatter] = [:]

    static func formatter(for code: String) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[code] {
            return existing
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        cache[code] = formatter
        return formatter
    }
}
