import Foundation
import SwiftData
import SwiftUI

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var inputMode: String = "voice" // "voice" or "text"
    var transcript: String = ""
    var summary: String = ""
    var duration: String = "0:00"
    var wordCount: Int = 0
    var isFavourite: Bool = false
    
    // AI Analysis Data
    var primaryEmotion: String = "Neutral"
    var intensity: Int = 5 // 1-10
    var energyLevel: Int = 5 // 1-10
    var valence: Double = 0.0 // -1.0 to 1.0
    var themes: [String] = []
    var followUpQuestion: String = ""
    var hiddenObservation: String = ""

    // Private reflection
    var note: String = ""

    // Set when this entry was created by responding to a question on another entry.
    var replyToEntryID: UUID?

    init(date: Date = Date(), inputMode: String = "voice", transcript: String = "", summary: String = "", duration: String = "0:00", wordCount: Int = 0, isFavourite: Bool = false, primaryEmotion: String = "Neutral", intensity: Int = 5, energyLevel: Int = 5, valence: Double = 0.0, themes: [String] = [], followUpQuestion: String = "", hiddenObservation: String = "", note: String = "", replyToEntryID: UUID? = nil) {
        self.date = date
        self.inputMode = inputMode
        self.transcript = transcript
        self.summary = summary
        self.duration = duration
        self.wordCount = wordCount
        self.isFavourite = isFavourite
        self.primaryEmotion = primaryEmotion
        self.intensity = intensity
        self.energyLevel = energyLevel
        self.valence = valence
        self.themes = themes
        self.followUpQuestion = followUpQuestion
        self.hiddenObservation = hiddenObservation
        self.note = note
        self.replyToEntryID = replyToEntryID
    }
    
    var emotionColor: Color {
        if valence > 0.3 { return Color(hex: "#10B981") }
        if valence < -0.3 { return Color(hex: "#EF4444") }
        return Color(hex: "#F59E0B")
    }
}
