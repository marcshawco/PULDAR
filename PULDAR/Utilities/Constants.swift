import SwiftUI

// MARK: - Color Palette

enum AppColors {
    static let background = Color(.systemBackground)
    static let secondaryBg = Color(.secondarySystemBackground)
    static let tertiaryBg = Color(.tertiarySystemBackground)

    // 3-Bucket colors — muted, premium tones
    static let bucketFundamentals = Color(red: 0.35, green: 0.55, blue: 0.78)
    static let bucketFun = Color(red: 0.55, green: 0.75, blue: 0.52)
    static let bucketFuture = Color(red: 0.68, green: 0.52, blue: 0.82)

    // Semantic
    static let overspend = Color(red: 0.92, green: 0.30, blue: 0.28)
    static let searchHighlight = Color.yellow.opacity(0.40)
    static let accent = Color(red: 0.30, green: 0.50, blue: 0.90)

    // Text
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
}

// MARK: - App-wide Constants

enum AppConstants {
    static let freeInputsPerWeek = 10
    static let proPrice = "$4.99"
    static let proProductID = "puldar_pro_lifetime"
    static let modelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    static let gpuCacheLimitBytes = 128 * 1024 * 1024 // 128 MB
}
