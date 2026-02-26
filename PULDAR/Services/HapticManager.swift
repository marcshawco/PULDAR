import UIKit

/// Centralised haptic feedback — keeps vibration logic out of views.
enum HapticManager {

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    // MARK: - Impact

    /// Soft tap for typing, scrolling, navigating tabs.
    static func light() {
        lightImpact.prepare()
        lightImpact.impactOccurred()
    }

    /// Slightly stronger for button presses.
    static func medium() {
        mediumImpact.prepare()
        mediumImpact.impactOccurred()
    }

    // MARK: - Notification

    /// Distinct triple-pulse for a successful expense log.
    static func success() {
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    /// Warning pulse when something goes wrong.
    static func warning() {
        notification.prepare()
        notification.notificationOccurred(.warning)
    }

    // MARK: - Selection

    /// Subtle click for selection changes.
    static func selection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }
}
