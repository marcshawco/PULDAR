import UIKit
import SwiftUI

/// Manages alternate app icon selection.
/// Icons are defined in Assets.xcassets as named icon sets and must be
/// included via ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES.
enum AppIcon: String, CaseIterable, Identifiable {
    case defaultIcon      = "Default"
    case whiteAppTint     = "White Tint"
    case ethereal         = "Ethereal"
    case etherealDark     = "Ethereal Dark"
    case etherealTint     = "Ethereal Tint"
    case black            = "Black"
    case blackTint        = "Black Tint"
    case pineapple        = "Pineapple"
    case pineappleDark    = "Pineapple Dark"
    case pineappleTint    = "Pineapple Tint"

    var id: String { rawValue }

    /// The asset catalog icon set name passed to `setAlternateIconName`.
    /// `nil` resets to the primary AppIcon.
    var iconName: String? {
        switch self {
        case .defaultIcon:   return nil
        case .whiteAppTint:  return "AppIcon-White-AppTint"
        case .ethereal:      return "AppIcon-Ethereal"
        case .etherealDark:  return "AppIcon-Ethereal-BlackBG"
        case .etherealTint:  return "AppIcon-Ethereal-AppTint"
        case .black:         return "AppIcon-Black"
        case .blackTint:     return "AppIcon-Black-AppTint"
        case .pineapple:     return "AppIcon-Pineapple"
        case .pineappleDark: return "AppIcon-Pineapple-BlackBG"
        case .pineappleTint: return "AppIcon-Pineapple-AppTint"
        }
    }

    var displayName: String { rawValue }

    /// Preview image name for the picker thumbnail (light-mode asset).
    var previewImageName: String {
        switch self {
        case .defaultIcon:   return "White_BlackBG"
        case .whiteAppTint:  return "White_AppTint"
        case .ethereal:      return "Ethereal_WhiteBG"
        case .etherealDark:  return "Ethereal_BlackBG"
        case .etherealTint:  return "Ethereal_AppTint"
        case .black:         return "Black_WhiteBG"
        case .blackTint:     return "Black_AppTint"
        case .pineapple:     return "Pineapple_WhiteBG"
        case .pineappleDark: return "Pineapple_BlackBG"
        case .pineappleTint: return "Pineapple_AppTint"
        }
    }
}

enum AppIconManager {

    static func apply(_ icon: AppIcon) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(icon.iconName)
    }

    static var current: AppIcon {
        guard let name = UIApplication.shared.alternateIconName else { return .defaultIcon }
        return AppIcon.allCases.first { $0.iconName == name } ?? .defaultIcon
    }
}
