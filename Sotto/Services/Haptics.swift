#if canImport(UIKit)
import UIKit
#endif

// MARK: - Centralised haptic feedback
// All haptics route through here so the Settings toggle ("hapticFeedback")
// controls them in one place.

@MainActor
enum Haptics {

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticFeedback") as? Bool ?? true
    }

    /// Light tap — tab switches, minor selections.
    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium thud — starting/stopping recording.
    static func impact() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Success notification — saved, favourited.
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification — destructive confirmations.
    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
