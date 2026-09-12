import Foundation

// MARK: - Pure statistics helpers (unit-testable, no SwiftData dependencies)

/// Pure arithmetic over entry data. `nonisolated` because none of it touches
/// UI state and the synthesis clustering calls it from an actor — under this
/// project's MainActor-by-default isolation it would otherwise be main-actor
/// bound for no reason.
nonisolated enum Stats {

    /// How many walked-back days must pass before another missed day can be
    /// forgiven. One miss per week, silently.
    private static let forgivenessWindowDays = 7

    /// Consecutive-day streak ending today or yesterday, from day-started dates.
    ///
    /// A single missed day is forgiven per rolling 7-day window, without
    /// telling the user or asking them to spend anything. Rationale: the
    /// failure mode of a strict streak isn't forgetting one day, it's
    /// abandoning the habit *because* the counter reset to zero — people
    /// with longer streaks quit harder after breaking one. Forgiving quietly
    /// keeps the encouragement and drops the punishment.
    ///
    /// A forgiven day is not *credited* — it keeps the streak alive but
    /// doesn't count as an entry, so the number still reflects real days
    /// written.
    static func currentStreak(days: Set<Date>, today: Date = Date(), calendar: Calendar = .current) -> Int {
        let written = Set(days.map { calendar.startOfDay(for: $0) })
        guard let earliest = written.min() else { return 0 }

        let startOfToday = calendar.startOfDay(for: today)
        // Not having written *yet today* was already never a break.
        var cursor = startOfToday
        if !written.contains(startOfToday) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
                  written.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        var daysWalked = 0
        var lastForgivenAt: Int?

        while cursor >= earliest {
            if written.contains(cursor) {
                streak += 1
            } else {
                let sinceLastForgiveness = lastForgivenAt.map { daysWalked - $0 } ?? .max
                guard sinceLastForgiveness >= forgivenessWindowDays else { break }
                lastForgivenAt = daysWalked
            }
            daysWalked += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Ratio of unique words to total words (0.0–1.0). Empty text returns 0.
    static func lexicalDiversity(_ text: String) -> Double {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0 }
        return Double(Set(words).count) / Double(words.count)
    }

    /// Most frequent element; nil for empty input.
    static func dominant<T: Hashable>(_ items: [T]) -> T? {
        var counts: [T: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Themes ranked by frequency across entries, capped at `limit`.
    static func topThemes(_ themeLists: [[String]], limit: Int = 12) -> [String] {
        var counts: [String: Int] = [:]
        for list in themeLists {
            for theme in list { counts[theme, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).map(\.key)
    }

    /// Share of `candidate` within `items` as 0.0–1.0.
    static func share<T: Hashable>(of candidate: T, in items: [T]) -> Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0 == candidate }.count) / Double(items.count)
    }
}
