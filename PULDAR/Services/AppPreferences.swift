import Foundation
import Observation

@Observable
@MainActor
final class AppPreferences {
    enum InputLanguage: String, CaseIterable, Identifiable {
        case english
        case french
        case italian
        case spanish

        var id: String { rawValue }

        var title: String {
            switch self {
            case .english: return "English"
            case .french: return "French"
            case .italian: return "Italian"
            case .spanish: return "Spanish"
            }
        }

        var parserInstruction: String {
            switch self {
            case .english:
                return "The user may write in English."
            case .french:
                return "The user may write in French. Understand French input, but always return the merchant in its normal display form and the category using one of the exact canonical category keys provided."
            case .italian:
                return "The user may write in Italian. Understand Italian input, but always return the merchant in its normal display form and the category using one of the exact canonical category keys provided."
            case .spanish:
                return "The user may write in Spanish. Understand Spanish input, but always return the merchant in its normal display form and the category using one of the exact canonical category keys provided."
            }
        }
    }

    enum CurrencyPreference: String, CaseIterable, Identifiable {
        case usd
        case eur
        case gbp
        case cad

        var id: String { rawValue }

        var code: String { rawValue.uppercased() }

        var title: String {
            switch self {
            case .usd: return "US Dollar (USD)"
            case .eur: return "Euro (EUR)"
            case .gbp: return "British Pound (GBP)"
            case .cad: return "Canadian Dollar (CAD)"
            }
        }
    }

    private enum StorageKey {
        static let inputLanguage = "appInputLanguage"
        static let currencyCode = "appCurrencyCode"
    }

    private let defaults = UserDefaults.standard

    var inputLanguage: InputLanguage {
        didSet { defaults.set(inputLanguage.rawValue, forKey: StorageKey.inputLanguage) }
    }

    var currencyPreference: CurrencyPreference {
        didSet { defaults.set(currencyPreference.rawValue, forKey: StorageKey.currencyCode) }
    }

    init() {
        inputLanguage = InputLanguage(
            rawValue: defaults.string(forKey: StorageKey.inputLanguage) ?? InputLanguage.english.rawValue
        ) ?? .english
        currencyPreference = CurrencyPreference(
            rawValue: defaults.string(forKey: StorageKey.currencyCode) ?? CurrencyPreference.usd.rawValue
        ) ?? .usd
    }

    var currencyCode: String {
        currencyPreference.code
    }
}
