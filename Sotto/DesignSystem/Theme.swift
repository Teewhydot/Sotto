import SwiftUI
import Observation

// MARK: - Theme model

struct Theme: Identifiable, Equatable {
    let id: String
    let accentHex: String          // primary brand accent (buttons, highlights)
    let accentDeepHex: String      // gradient partner for CTAs / mic button
    let warmHex: String            // secondary warm tone used on gradients

    var accent: Color { Color(hex: accentHex) }
    var deep: Color { Color(hex: accentDeepHex) }
    var warm: Color { Color(hex: warmHex) }

    static let all: [Theme] = [.indigo, .rose, .slate]

    static let indigo = Theme(id: "Indigo",  accentHex: "#E07A5F", accentDeepHex: "#6366F1", warmHex: "#F2CC8F")
    static let rose   = Theme(id: "Rose",    accentHex: "#D65A7E", accentDeepHex: "#BE3455", warmHex: "#F6C1A7")
    static let slate  = Theme(id: "Slate",   accentHex: "#5B7C99", accentDeepHex: "#3F5871", warmHex: "#A8C3D9")

    static func named(_ name: String) -> Theme {
        all.first { $0.id == name } ?? .indigo
    }
}

// MARK: - Manager

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private static let storageKey = "appTheme"

    /// The active theme. Persisted to UserDefaults on change.
    private(set) var current: Theme {
        didSet { UserDefaults.standard.set(current.id, forKey: Self.storageKey) }
    }

    private init() {
        current = Theme.named(UserDefaults.standard.string(forKey: Self.storageKey) ?? Theme.indigo.id)
    }

    func select(_ theme: Theme) {
        current = theme
    }
}

// MARK: - Palette bridge
// sottoAccent is now dynamic — it follows the selected theme. Views re-render
// when the tree's root observes ThemeManager (see SottoApp).

extension Color {
    static var sottoAccent: Color { ThemeManager.shared.current.accent }
}
