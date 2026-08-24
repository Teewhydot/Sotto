import XCTest
import SwiftUI
@testable import Sotto

final class JournalEntryTests: XCTestCase {

    func testJournalEntryInitialization() {
        let entry = JournalEntry(
            date: Date(),
            transcript: "I feel great today.",
            summary: "A great day.",
            wordCount: 4,
            primaryEmotion: "Joyful",
            intensity: 8,
            energyLevel: 9,
            valence: 0.8,
            themes: ["work", "health"],
            followUpQuestion: "What made it great?",
            hiddenObservation: "Seems energetic.",
            note: "Remember this feeling"
        )

        XCTAssertEqual(entry.transcript, "I feel great today.")
        XCTAssertEqual(entry.summary, "A great day.")
        XCTAssertEqual(entry.primaryEmotion, "Joyful")
        XCTAssertEqual(entry.wordCount, 4)
        XCTAssertEqual(entry.note, "Remember this feeling")
        XCTAssertEqual(entry.inputMode, "voice")
        XCTAssertNil(entry.replyToEntryID)
    }

    func testReplyLinkage() {
        let parentID = UUID()
        let reply = JournalEntry(transcript: "A reply.", replyToEntryID: parentID)
        XCTAssertEqual(reply.replyToEntryID, parentID)
    }

    func testDefaults() {
        let entry = JournalEntry()
        XCTAssertEqual(entry.inputMode, "voice")
        XCTAssertEqual(entry.primaryEmotion, "Neutral")
        XCTAssertEqual(entry.intensity, 5)
        XCTAssertEqual(entry.valence, 0.0)
        XCTAssertFalse(entry.isFavourite)
    }

    func testJournalEntryEmotionColors() {
        let positive = JournalEntry(valence: 0.5)
        XCTAssertEqual(positive.emotionColor, Color(hex: "#10B981"))

        let negative = JournalEntry(valence: -0.5)
        XCTAssertEqual(negative.emotionColor, Color(hex: "#EF4444"))

        let neutral = JournalEntry(valence: 0.1)
        XCTAssertEqual(neutral.emotionColor, Color(hex: "#F59E0B"))
    }
}
