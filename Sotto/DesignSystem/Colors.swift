import SwiftUI

// MARK: - Hex Color initialiser
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Sotto Palette
extension Color {
    // Backgrounds (adapts to light/dark)
    static let sottoBackground  = Color(.systemBackground)
    static let sottoSecondary   = Color(.secondarySystemBackground)
    static let sottoTertiary    = Color(.tertiarySystemBackground)

    // Recording screen — always dark
    static let sottoRecordingBG = Color(hex: "#000000")

    // Brand accent is dynamic — see Theme.swift / ThemeManager.

    // Emotion semantic colours
    static let emotionPositive  = Color(hex: "#10B981")   // emerald
    static let emotionNeutral   = Color(hex: "#F59E0B")   // amber
    static let emotionNegative  = Color(hex: "#EF4444")   // red
    static let emotionMixed     = Color(hex: "#8B5CF6")   // violet
}

// MARK: - Per-emotion colour helper
extension Color {
    static func forEmotion(_ emotion: String) -> Color {
        switch emotion.lowercased() {
        case "joyful", "grateful", "excited":          return Color(hex: "#10B981")
        case "content", "hopeful", "relieved", "calm": return Color(hex: "#34D399")
        case "loving", "proud":                        return Color(hex: "#EC4899")
        case "reflective", "curious", "nostalgic":     return Color(hex: "#F59E0B")
        case "uncertain", "ambivalent", "neutral":     return Color(hex: "#9CA3AF")
        case "anxious", "fearful":                     return Color(hex: "#F97316")
        case "frustrated", "angry":                    return Color(hex: "#EF4444")
        case "sad", "grieving", "lonely":              return Color(hex: "#6B7280")
        case "overwhelmed", "exhausted", "numb":       return Color(hex: "#374151")
        case "conflicted", "disappointed":             return Color(hex: "#8B5CF6")
        default:                                       return Color(hex: "#9CA3AF")
        }
    }
}
