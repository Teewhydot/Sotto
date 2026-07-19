import XCTest
@testable import Sotto

final class JournalEntryTests: XCTestCase {
    
    func testJournalEntryInitialization() {
        let entry = JournalEntry(
            id: UUID(),
            date: Date(),
            transcript: "I feel great today.",
            summary: "A great day.",
            primaryEmotion: "Joyful",
            intensity: 8,
            energyLevel: 9,
            valence: 0.8,
            themes: ["work", "health"],
            followUpQuestion: "What made it great?",
            hiddenObservation: "Seems energetic.",
            durationSeconds: 120,
            wordCount: 4
        )
        
        XCTAssertEqual(entry.transcript, "I feel great today.")
        XCTAssertEqual(entry.primaryEmotion, "Joyful")
        XCTAssertEqual(entry.wordCount, 4)
    }
    
    func testJournalEntryEmotionColors() {
        let positiveEntry = JournalEntry(id: UUID(), date: Date(), transcript: "", summary: "", primaryEmotion: "Joyful", intensity: 1, energyLevel: 1, valence: 0.5, themes: [], followUpQuestion: "", hiddenObservation: "", durationSeconds: 0, wordCount: 0)
        XCTAssertEqual(positiveEntry.emotionColor.description, "#10B981")
        
        let negativeEntry = JournalEntry(id: UUID(), date: Date(), transcript: "", summary: "", primaryEmotion: "Sad", intensity: 1, energyLevel: 1, valence: -0.5, themes: [], followUpQuestion: "", hiddenObservation: "", durationSeconds: 0, wordCount: 0)
        XCTAssertEqual(negativeEntry.emotionColor.description, "#EF4444")
        
        let neutralEntry = JournalEntry(id: UUID(), date: Date(), transcript: "", summary: "", primaryEmotion: "Reflective", intensity: 1, energyLevel: 1, valence: 0.1, themes: [], followUpQuestion: "", hiddenObservation: "", durationSeconds: 0, wordCount: 0)
        XCTAssertEqual(neutralEntry.emotionColor.description, "#F59E0B")
    }
}
