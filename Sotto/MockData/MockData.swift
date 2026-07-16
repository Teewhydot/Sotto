//
//  MockData.swift
//  Sotto
//

import SwiftUI

// MARK: - MockEntry model
struct MockEntry: Identifiable {
    let id = UUID()
    let date: Date
    let transcript: String
    let duration: String
    let wordCount: Int
    let inputMode: String      // "voice" or "text"
    let primaryEmotion: String
    let emotionColor: Color
    let valence: Double        // -1.0 to 1.0
    let intensity: Int         // 1–10
    let energyLevel: Int       // 1–10
    let themes: [String]
    let followUpQuestion: String
    let hiddenObservation: String
    let isFavourite: Bool
}

// MARK: - Mock entries
let mockEntries: [MockEntry] = [
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: 0, to: Date())!,
        transcript: "I've been thinking about the conversation we had yesterday and whether I handled it the right way. I keep coming back to the moment when I said something that I didn't mean to say in that way. I think I was trying to be direct but it came out differently. It's been sitting with me all day. I don't know if I should bring it up again or just let it pass. I hate that feeling of things being unresolved.",
        duration: "1m 47s",
        wordCount: 84,
        inputMode: "voice",
        primaryEmotion: "Reflective",
        emotionColor: Color(hex: "#F59E0B"),
        valence: -0.2,
        intensity: 6,
        energyLevel: 5,
        themes: ["communication", "self-doubt", "relationships", "past decisions"],
        followUpQuestion: "What would it feel like to let go of the part you can't control?",
        hiddenObservation: "You mentioned 'I don't know' four times without asking a single question.",
        isFavourite: false
    ),
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
        transcript: "Today was genuinely good. I finished the project I've been avoiding for two weeks and it felt lighter than I expected. There's something about getting a thing done that makes you realise you were carrying it more than you knew. I treated myself to a really good meal and just sat with the quiet for a bit. I want more days like this.",
        duration: "2m 12s",
        wordCount: 67,
        inputMode: "voice",
        primaryEmotion: "Grateful",
        emotionColor: Color(hex: "#10B981"),
        valence: 0.8,
        intensity: 5,
        energyLevel: 8,
        themes: ["productivity", "rest", "gratitude", "self-care"],
        followUpQuestion: "What made today feel different from other good days?",
        hiddenObservation: "You used the word 'quiet' in a way that sounded like relief, not loneliness.",
        isFavourite: true
    ),
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
        transcript: "I don't really know what to say today. I'm tired but not in a physical way. More like background tired. The kind that's been there a while. I went through the motions at work and came home and sat on the couch longer than I meant to.",
        duration: "55s",
        wordCount: 47,
        inputMode: "voice",
        primaryEmotion: "Exhausted",
        emotionColor: Color(hex: "#374151"),
        valence: -0.6,
        intensity: 4,
        energyLevel: 2,
        themes: ["fatigue", "work", "disconnection"],
        followUpQuestion: "When did this kind of tired start — was there a specific moment?",
        hiddenObservation: "You said 'I don't know' before saying anything else.",
        isFavourite: false
    ),
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: -4, to: Date())!,
        transcript: "Had a really interesting conversation with my sister today. She's going through something similar to what I went through last year and I could hear myself in what she was saying. I gave her advice I wish someone had given me. It felt meaningful. Also the weather was perfect and I went for a walk which helped everything.",
        duration: "3m 02s",
        wordCount: 61,
        inputMode: "voice",
        primaryEmotion: "Content",
        emotionColor: Color(hex: "#34D399"),
        valence: 0.65,
        intensity: 6,
        energyLevel: 7,
        themes: ["family", "connection", "growth", "nature"],
        followUpQuestion: "What did giving that advice teach you about where you are now?",
        hiddenObservation: "You talked about your sister but kept returning to what you needed a year ago.",
        isFavourite: false
    ),
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
        transcript: "Work is overwhelming right now. There are three different things all needing to be urgent at the same time and I'm the person who has to hold all of it. I don't think anyone else sees how much is being carried. I'm frustrated and I'm trying not to show it but it's getting harder.",
        duration: "1m 23s",
        wordCount: 58,
        inputMode: "voice",
        primaryEmotion: "Overwhelmed",
        emotionColor: Color(hex: "#374151"),
        valence: -0.75,
        intensity: 8,
        energyLevel: 3,
        themes: ["work", "stress", "recognition", "boundaries"],
        followUpQuestion: "What would need to be true for you to feel like you're not carrying this alone?",
        hiddenObservation: "You said 'I'm trying' twice — both times it sounded like an apology.",
        isFavourite: false
    ),
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
        transcript: "Feeling anxious about next week. The presentation is big and I keep running through scenarios where things go wrong. I know I'm prepared. I know the material. But there's this voice that keeps asking what if. It's loud today.",
        duration: "1m 10s",
        wordCount: 52,
        inputMode: "voice",
        primaryEmotion: "Anxious",
        emotionColor: Color(hex: "#F97316"),
        valence: -0.5,
        intensity: 7,
        energyLevel: 6,
        themes: ["anxiety", "work", "performance", "self-doubt"],
        followUpQuestion: "What does the voice sound like — whose voice is it?",
        hiddenObservation: "You said 'I know' twice as reassurance, then immediately contradicted it.",
        isFavourite: false
    ),
    MockEntry(
        date: Calendar.current.date(byAdding: .day, value: -9, to: Date())!,
        transcript: "I'm excited about the project. Genuinely excited in a way I haven't felt in a while. It's early and messy but there's something real there. I spent four hours on it without noticing the time. That's always the sign.",
        duration: "58s",
        wordCount: 44,
        inputMode: "voice",
        primaryEmotion: "Excited",
        emotionColor: Color(hex: "#10B981"),
        valence: 0.9,
        intensity: 8,
        energyLevel: 9,
        themes: ["creativity", "work", "flow", "purpose"],
        followUpQuestion: "What specifically felt real about it — the idea, or the act of working on it?",
        hiddenObservation: "You described losing track of time like proof of something, not coincidence.",
        isFavourite: true
    ),
]

// MARK: - Weekly brief
let mockWeeklyBrief = (
    narrative: "You moved through a lot of uncertainty this week. Work kept surfacing even in your quieter entries, and there's a thread of wanting to be seen for what you're carrying that ran through almost everything you wrote. Something is asking for your attention underneath the busyness.",
    dominantEmotion: "Reflective",
    patternObservation: "Your energy tended to drop mid-week but showed signs of recovering toward the weekend — the good day on Tuesday seems to have been a genuine reset.",
    invitation: "You might notice what it feels like to finish a day without going over what's unresolved.",
    topThemes: ["work", "self-doubt", "communication"],
    averageValence: -0.12,
    entryCount: 5
)

// MARK: - Calendar mood data (30 days of valences, nil = no entry)
let mockCalendarData: [Date: Double?] = {
    var data: [Date: Double?] = [:]
    let entries: [(Int, Double?)] = [
        (0, -0.2), (1, 0.8), (2, -0.6), (3, nil),
        (4, 0.65), (5, -0.75), (6, nil), (7, -0.5),
        (8, nil), (9, 0.9), (10, 0.3), (11, -0.4),
        (12, 0.6), (13, nil), (14, -0.3), (15, 0.7),
        (16, -0.8), (17, nil), (18, 0.5), (19, -0.1),
        (20, nil), (21, 0.4), (22, -0.5), (23, 0.2),
        (24, nil), (25, -0.3), (26, 0.6), (27, nil),
        (28, 0.1), (29, -0.2)
    ]
    for (daysAgo, valence) in entries {
        if let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) {
            data[date] = valence
        }
    }
    return data
}()

// MARK: - Emotion emoji helper (global so all views can use it)
func emotionEmoji(for emotion: String) -> String {
    let map: [String: String] = [
        "Reflective": "🪞", "Grateful": "🌿", "Excited": "✨",
        "Content": "☀️", "Anxious": "🌀", "Overwhelmed": "🌊",
        "Exhausted": "🌑", "Sad": "🌧️", "Angry": "🔥",
        "Loving": "🌸", "Proud": "🏆", "Curious": "🔭",
        "Hopeful": "🌤️", "Calm": "🍃"
    ]
    return map[emotion] ?? "◦"
}
