import UIKit

/// Centralised haptic feedback — keeps vibration logic out of views.
enum HapticManager {

    // MARK: - Impact

    /// Soft tap for typing, scrolling, navigating tabs.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Slightly stronger for button presses.
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Notification

    /// Distinct triple-pulse for a successful expense log.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning pulse when something goes wrong.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    // MARK: - Selection

    /// Subtle click for selection changes.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
