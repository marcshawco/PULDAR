import SwiftUI

/// The 50 / 30 / 20 psychological budgeting framework.
enum BudgetBucket: String, Codable, CaseIterable, Identifiable {
    case fundamentals = "Fundamentals"
    case fun          = "Fun"
    case future       = "Future"

    var id: String { rawValue }

    /// Default share of monthly income.
    var defaultPercentage: Double {
        switch self {
        case .fundamentals: return 0.50
        case .fun:          return 0.30
        case .future:       return 0.20
        }
    }

    /// Human-friendly subtitle shown under the bucket name.
    var subtitle: String {
        switch self {
        case .fundamentals: return "Needs"
        case .fun:          return "Wants"
        case .future:       return "Savings & Debt"
        }
    }

    var infoExplanation: String {
        switch self {
        case .fundamentals:
            return "Fundamentals covers your core needs and essential bills. Think rent, groceries, utilities, insurance, gas, and phone service."
        case .fun:
            return "Fun is for flexible lifestyle spending and wants. Think dining out, shopping, subscriptions, travel, coffee, hobbies, and entertainment."
        case .future:
            return "Future is money you set aside to strengthen your future finances. Think savings, investing, retirement, extra debt payments, emergency funds, and education."
        }
    }

    /// SF Symbol for each bucket.
    var icon: String {
        switch self {
        case .fundamentals: return "house"
        case .fun:          return "sparkles"
        case .future:       return "chart.line.uptrend.xyaxis"
        }
    }

    /// Colour mapped from the app palette.
    var color: Color {
        switch self {
        case .fundamentals: return AppColors.bucketFundamentals
        case .fun:          return AppColors.bucketFun
        case .future:       return AppColors.bucketFuture
        }
    }
}
