import Foundation
import SwiftUI

func emotionEmoji(for emotion: String) -> String {
    switch emotion.lowercased() {
    case "reflective": return "🤔\u{FE0F}"
    case "grateful": return "🙏\u{FE0F}"
    case "overwhelmed": return "🌊\u{FE0F}"
    case "anxious": return "🦋\u{FE0F}"
    case "joyful", "content": return "☀️\u{FE0F}"
    case "frustrated": return "😤\u{FE0F}"
    case "exhausted": return "🔋\u{FE0F}"
    case "inspired": return "✨\u{FE0F}"
    case "sad": return "🌧️\u{FE0F}"
    case "angry": return "🔥\u{FE0F}"
    case "hopeful": return "🌱\u{FE0F}"
    case "lonely": return "🧊\u{FE0F}"
    case "peaceful": return "🕊️\u{FE0F}"
    default: return "💬\u{FE0F}"
    }
}
