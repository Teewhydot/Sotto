import Foundation
import SwiftData

// MARK: - Preview & test support
// In-memory sample entries for SwiftUI previews. Never used at runtime.

enum MockData {

    static func makeContainer(entries: [JournalEntry] = sampleEntries) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: JournalEntry.self, configurations: config)
        let context = ModelContext(container)
        for entry in entries { context.insert(entry) }
        try? context.save()
        return container
    }

    static var previewContainer: ModelContainer { makeContainer() }

    static var sampleEntries: [JournalEntry] = [
        JournalEntry(
            date: Date(timeIntervalSinceNow: -3600),
            inputMode: "voice",
            transcript: "Today felt lighter than I expected. I finally had the conversation I'd been putting off all week, and it went better than the version in my head. There's still a knot about what comes next, but at least the knot has a name now.",
            summary: "A feared conversation went well, leaving relief mixed with uncertainty about next steps.",
            duration: "3m 12s",
            wordCount: 48,
            isFavourite: true,
            primaryEmotion: "Relieved",
            intensity: 6,
            energyLevel: 5,
            valence: 0.55,
            themes: ["courage", "relationships", "uncertainty"],
            followUpQuestion: "What would make the 'what comes next' feel less heavy?",
            hiddenObservation: "You rehearsed this conversation mentally for days — naming things early tends to shrink them for you.",
        ),
        JournalEntry(
            date: Date(timeIntervalSinceNow: -86_400 * 2),
            inputMode: "text",
            transcript: "Drained after back-to-back meetings. I notice I say yes before checking whether I have room to actually deliver. Want to sit with why approval feels urgent lately.",
            summary: "Meeting fatigue and a pattern of overcommitting tied to a need for approval.",
            duration: "0m 45s",
            wordCount: 31,
            primaryEmotion: "Exhausted",
            intensity: 7,
            energyLevel: 2,
            valence: -0.4,
            themes: ["work", "boundaries", "approval"],
            followUpQuestion: "What would a graceful no sound like tomorrow?",
            hiddenObservation: "Your yeses are often purchased with future exhaustion — the price is paid by evening-you.",
        ),
        JournalEntry(
            date: Date(timeIntervalSinceNow: -86_400 * 4),
            inputMode: "voice",
            transcript: "Morning walk along the river. The light was that pale gold that only happens in late summer. Felt quietly hopeful about nothing in particular.",
            summary: "A peaceful morning walk sparked diffuse, quiet hopefulness.",
            duration: "2m 05s",
            wordCount: 27,
            primaryEmotion: "Peaceful",
            intensity: 4,
            energyLevel: 6,
            valence: 0.7,
            themes: ["nature", "gratitude"],
            followUpQuestion: "Where else in your week could that kind of stillness fit?",
            hiddenObservation: "Hope arrived when you stopped asking it to be about anything specific.",
        ),
    ]
}
