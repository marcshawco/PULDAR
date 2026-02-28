import SwiftUI

extension View {
    /// Trigger a light haptic when this view appears.
    func hapticOnAppear() -> some View {
        self.onAppear { HapticManager.light() }
    }

    /// Trigger a light haptic on tap (in addition to the tap action).
    func hapticTap(perform action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            HapticManager.light()
            action()
        }
    }
}
