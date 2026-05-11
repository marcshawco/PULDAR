import SwiftUI

// MARK: - Color Palette (Warm monochrome + three bucket accents)

enum AppColors {
    // Backgrounds
    static let background = Color("bg")
    static let secondaryBg = Color("surface")
    static let tertiaryBg = Color("surf2")

    // 3-Bucket colors — the only non-monochrome colours in the app
    static let bucketFundamentals = Color("bucketFundamentals")
    static let bucketFun = Color("bucketFun")
    static let bucketFuture = Color("bucketFuture")

    // Semantic
    static let overspend = Color("danger")
    static let success = Color("success")
    static let searchHighlight = Color.yellow.opacity(0.40)
    static let accent = Color("text1")

    // Text
    static let textPrimary = Color("text1")
    static let textSecondary = Color("text2")
    static let textTertiary = Color("text3")

    // Hairline border
    static let border = Color("border")
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
