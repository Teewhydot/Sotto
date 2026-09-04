import Foundation
import SwiftUI

extension String {
    /// Truncates to `limit` characters, appending an ellipsis only when
    /// something was actually cut — a bare `prefix(n) + "…"` marks short,
    /// untruncated text as cut off too.
    func truncated(to limit: Int) -> String {
        count > limit ? String(prefix(limit)) + "…" : self
    }
}

/// Returns a short neutral placeholder string for the given emotion.
/// This function no longer returns emoji or emoji sequences.
func emotionEmoji(for emotion: String) -> String {
    switch emotion.lowercased() {
    case "reflective": return "–"
    case "grateful": return "–"
    case "overwhelmed": return "–"
    case "anxious": return "–"
    case "joyful", "content": return "–"
    case "frustrated": return "–"
    case "exhausted": return "–"
    case "inspired": return "–"
    case "sad": return "–"
    case "angry": return "–"
    case "hopeful": return "–"
    case "lonely": return "–"
    case "peaceful": return "–"
    default: return "–"
    }
}
