import XCTest
@testable import Sotto

final class StatsTests: XCTestCase {

    private func day(_ offset: Int, from today: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: -offset, to: start)!
    }

    // MARK: - Streaks

    func testStreakEmpty() {
        XCTAssertEqual(Stats.currentStreak(days: []), 0)
    }

    func testStreakTodayOnly() {
        XCTAssertEqual(Stats.currentStreak(days: [day(0)]), 1)
    }

    func testStreakConsecutiveDays() {
        let days: Set<Date> = [day(0), day(1), day(2), day(3)]
        XCTAssertEqual(Stats.currentStreak(days: days), 4)
    }

    func testStreakYesterdayCountsWhenTodayMissing() {
        let days: Set<Date> = [day(1), day(2)]
        XCTAssertEqual(Stats.currentStreak(days: days), 2)
    }

    func testStreakBreakResets() {
        let days: Set<Date> = [day(0), day(2)]
        XCTAssertEqual(Stats.currentStreak(days: days), 1)
    }

    func testStreakGapAfterYesterday() {
        let days: Set<Date> = [day(3), day(4)]
        XCTAssertEqual(Stats.currentStreak(days: days), 0)
    }

    // MARK: - Lexical diversity

    func testLexicalDiversityEmptyText() {
        XCTAssertEqual(Stats.lexicalDiversity(""), 0)
        XCTAssertEqual(Stats.lexicalDiversity("   "), 0)
    }

    func testLexicalDiversityAllUnique() {
        XCTAssertEqual(Stats.lexicalDiversity("a b c d"), 1.0, accuracy: 0.0001)
    }

    func testLexicalDiversityRepeats() {
        // "a b a b" → 2 unique of 4 total
        XCTAssertEqual(Stats.lexicalDiversity("a b a b"), 0.5, accuracy: 0.0001)
    }

    func testLexicalDiversityIgnoresPunctuationAndCase() {
        XCTAssertEqual(Stats.lexicalDiversity("Hello, hello! HELLO"), 1.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - Dominant / themes / share

    func testDominantReturnsMode() {
        XCTAssertEqual(Stats.dominant(["calm", "anxious", "calm"]), "calm")
        XCTAssertNil(Stats.dominant([Int]()))
    }

    func testTopThemesRanksByFrequency() {
        let ranked = Stats.topThemes(
            [["work", "family"], ["work"], ["work", "health", "family"]],
            limit: 10
        )
        XCTAssertEqual(ranked.first, "work")
        XCTAssertTrue(ranked.contains("family"))
        // work, family, health — three distinct themes
        XCTAssertEqual(ranked.count, 3)
    }

    func testTopThemesRespectsLimit() {
        let ranked = Stats.topThemes([["a", "b", "c"]], limit: 2)
        XCTAssertEqual(ranked.count, 2)
    }

    func testShare() {
        XCTAssertEqual(Stats.share(of: "x", in: ["x", "y", "x", "z"]), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Stats.share(of: "x", in: []), 0)
    }

    // MARK: - Audio helpers

    func testResamplePassthroughSameRate() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        XCTAssertEqual(SpeechService.resample(samples, from: 16_000, to: 16_000), samples)
    }

    func testResampleHalvingRate() {
        let samples: [Float] = Array(stride(from: 0.0, to: 100.0, by: 1.0)).map(Float.init)
        let down = SpeechService.resample(samples, from: 32_000, to: 16_000)
        XCTAssertEqual(down.count, 50, accuracy: 1)
        // Linear interpolation should land close to original even-indexed values.
        XCTAssertEqual(down[1], samples[2], accuracy: 1.01)
    }

    func testWavHeaderSize() throws {
        let url = try XCTUnwrap(SpeechService.writeTemporaryWav(samples: [0.0, 1.0], sampleRate: 16_000))
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        // 44-byte canonical PCM header + 2 samples × 2 bytes (Int16)
        XCTAssertEqual(data.count, 48)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        // fmt chunk: PCM format tag
        let audioFormat = data.subdata(in: 20..<22)
        XCTAssertEqual(audioFormat, Data([0x01, 0x00]))
    }
}
