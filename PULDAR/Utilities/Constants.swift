import SwiftUI

// MARK: - Color Palette

enum AppColors {
    static let background = Color(.systemBackground)
    static let secondaryBg = Color(.secondarySystemBackground)
    static let tertiaryBg = Color(.tertiarySystemBackground)

    // 3-Bucket colors — the only non-monochrome colours in the app
    static let bucketFundamentals = Color(red: 0.227, green: 0.361, blue: 0.678) // #3A5CAD
    static let bucketFun = Color(red: 0.165, green: 0.502, blue: 0.337)          // #2A8056
    static let bucketFuture = Color(red: 0.788, green: 0.412, blue: 0.141)       // #C96924

    // Semantic
    static let overspend = Color(red: 0.753, green: 0.224, blue: 0.169) // #C0392B
    static let success = Color(red: 0.153, green: 0.682, blue: 0.376)   // #27AE60
    static let searchHighlight = Color.yellow.opacity(0.40)
    static let accent = Color(.label)

    // Text
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    // Hairline border
    static let border = Color(red: 0.89, green: 0.88, blue: 0.85) // #E3E0D8
}

// MARK: - App-wide Constants

enum AppConstants {
    static let freeInputsPerMonth = 10
    static let proPrice = "14-day trial, then $4.99/mo or $49.99/yr"
    static let proMonthlyProductID = "puldar_pro_monthly"
    static let proYearlyProductID = "puldar_pro_yearly"
    static let legacyProLifetimeProductID = "puldar_pro_lifetime"
    static let modelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    static let gpuCacheLimitBytes = 128 * 1024 * 1024 // 128 MB
}
