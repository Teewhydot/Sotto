import Foundation

// MARK: - Pure statistics helpers (unit-testable, no SwiftData dependencies)

enum Stats {

    /// Consecutive-day streak ending today or yesterday, from day-started dates.
    static func currentStreak(days: Set<Date>, today: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !days.isEmpty else { return 0 }
        let startOfToday = calendar.startOfDay(for: today)
        var expected = startOfToday
        if !days.contains(startOfToday) {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            guard days.contains(yesterday) else { return 0 }
            expected = yesterday
        }
        var streak = 0
        for day in days.sorted(by: >) {
            if calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else if day < expected {
                break
            }
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
