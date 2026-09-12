import XCTest
@testable import Sotto

/// Tests for the deterministic half of Smart Insights.
///
/// Clustering and the output guard are the parts that decide what a paying
/// user is told, and neither needs a language model to exercise — which is
/// the point of keeping them pure.
final class SynthesisTests: XCTestCase {

    // MARK: Builders

    private func entry(
        day: Int,
        themes: [String],
        valence: Double = 0,
        emotion: String = "Reflective",
        intensity: Int = 5,
        transcript: String = "An entry."
    ) -> SynthesisEntry {
        let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        return SynthesisEntry(
            id: UUID(),
            date: Calendar.current.date(byAdding: .day, value: -day, to: base)!,
            transcript: transcript,
            primaryEmotion: emotion,
            themes: themes,
            valence: valence,
            intensity: intensity
        )
    }

    // MARK: - Minimum support

    func testNoClustersBelowMinimumEntries() {
        let entries = [entry(day: 0, themes: ["work"]), entry(day: 1, themes: ["work"])]
        XCTAssertTrue(SynthesisClustering.clusters(from: entries).isEmpty)
    }

    func testThemeNeedsThreeEntriesToBecomeAPattern() {
        // "work" appears twice, "sleep" three times. Only sleep is a pattern.
        let entries = [
            entry(day: 0, themes: ["work", "sleep"]),
            entry(day: 1, themes: ["work", "sleep"]),
            entry(day: 2, themes: ["sleep"]),
        ]
        let themes = SynthesisClustering.clusters(from: entries).map(\.theme)
        XCTAssertEqual(themes, ["sleep"])
    }

    // MARK: - Normalisation

    func testThemeMatchingIgnoresCaseAndWhitespace() {
        let entries = [
            entry(day: 0, themes: ["Work"]),
            entry(day: 1, themes: [" work "]),
            entry(day: 2, themes: ["WORK"]),
        ]
        let clusters = SynthesisClustering.clusters(from: entries)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.theme, "work")
        XCTAssertEqual(clusters.first?.support, 3)
    }

    func testRepeatedThemeWithinOneEntryCountsOnce() {
        // A model can emit the same theme twice for one entry. If that
        // inflated support, two entries could masquerade as a pattern.
        let entries = [
            entry(day: 0, themes: ["work", "Work", " work"]),
            entry(day: 1, themes: ["work"]),
        ]
        XCTAssertTrue(SynthesisClustering.clusters(from: entries).isEmpty)
    }

    func testUninformativeThemesAreDropped() {
        let entries = [
            entry(day: 0, themes: ["life", "thoughts", "deadlines"]),
            entry(day: 1, themes: ["today", "feelings", "deadlines"]),
            entry(day: 2, themes: ["journal", "self", "deadlines"]),
        ]
        XCTAssertEqual(SynthesisClustering.clusters(from: entries).map(\.theme), ["deadlines"])
    }

    func testVeryShortThemesAreDropped() {
        let entries = (0..<3).map { entry(day: $0, themes: ["ok", "a", "money"]) }
        XCTAssertEqual(SynthesisClustering.clusters(from: entries).map(\.theme), ["money"])
    }

    // MARK: - Support vs sample

    /// Regression: `support` used to be `entries.count`, which was the capped
    /// sample. A theme in nine entries was then presented as "6 of your N",
    /// understating the evidence for the claim on screen.
    func testSupportReportsEveryMatchNotJustTheSample() {
        let entries = (0..<9).map { entry(day: $0, themes: ["money"], valence: -0.5) }
        let cluster = try! XCTUnwrap(SynthesisClustering.clusters(from: entries).first)

        XCTAssertEqual(cluster.support, 9, "support must count every matching entry")
        XCTAssertEqual(
            cluster.entries.count,
            SynthesisClustering.maximumEntriesPerCluster,
            "the prompt sample stays capped"
        )
        XCTAssertTrue(cluster.hasMoreEvidenceThanShown)
    }

    func testSampleIsTheMostRecentEntries() {
        let entries = (0..<8).map { entry(day: $0, themes: ["money"]) }
        let cluster = try! XCTUnwrap(SynthesisClustering.clusters(from: entries).first)
        // day: 0 is the newest, so the sample must start there.
        XCTAssertEqual(cluster.entries.first?.id, entries[0].id)
        XCTAssertEqual(cluster.entries.count, 6)
    }

    // MARK: - Valence delta

    func testValenceDeltaIsRelativeToThePeriodBaseline() {
        // Baseline is 0; the "money" entries average -0.6.
        let entries = [
            entry(day: 0, themes: ["money"], valence: -0.6),
            entry(day: 1, themes: ["money"], valence: -0.6),
            entry(day: 2, themes: ["money"], valence: -0.6),
            entry(day: 3, themes: ["friends"], valence: 0.6),
            entry(day: 4, themes: ["friends"], valence: 0.6),
            entry(day: 5, themes: ["friends"], valence: 0.6),
        ]
        let clusters = SynthesisClustering.clusters(from: entries)
        let money = try! XCTUnwrap(clusters.first { $0.theme == "money" })
        let friends = try! XCTUnwrap(clusters.first { $0.theme == "friends" })

        XCTAssertEqual(money.valenceDelta, -0.6, accuracy: 0.0001)
        XCTAssertEqual(friends.valenceDelta, 0.6, accuracy: 0.0001)
    }

    func testATagAtTheBaselineHasNoDelta() {
        let entries = (0..<4).map { entry(day: $0, themes: ["routine"], valence: 0.2) }
        let cluster = try! XCTUnwrap(SynthesisClustering.clusters(from: entries).first)
        XCTAssertEqual(cluster.valenceDelta, 0, accuracy: 0.0001)
    }

    // MARK: - Ranking

    func testAThemeThatMovesTheNeedleOutranksANeutralOne() {
        // Both recur three times; only "money" departs from the baseline.
        let entries = [
            entry(day: 0, themes: ["money", "commute"], valence: -0.8),
            entry(day: 1, themes: ["money", "commute"], valence: -0.8),
            entry(day: 2, themes: ["money", "commute"], valence: -0.8),
            entry(day: 3, themes: ["commute"], valence: 0.8),
            entry(day: 4, themes: ["commute"], valence: 0.8),
            entry(day: 5, themes: ["commute"], valence: 0.8),
        ]
        let clusters = SynthesisClustering.clusters(from: entries)
        XCTAssertEqual(clusters.first?.theme, "money")
    }

    func testAtMostThreePatterns() {
        var entries: [SynthesisEntry] = []
        for theme in ["work", "sleep", "money", "family", "health"] {
            for day in 0..<3 {
                entries.append(entry(day: day, themes: [theme], valence: Double(day) * -0.2))
            }
        }
        XCTAssertEqual(
            SynthesisClustering.clusters(from: entries).count,
            SynthesisClustering.maximumClusters
        )
    }

    func testOrderingIsStableAcrossRuns() {
        var entries: [SynthesisEntry] = []
        for theme in ["work", "sleep", "money"] {
            for day in 0..<3 { entries.append(entry(day: day, themes: [theme])) }
        }
        // Identical input must give identical output every time: a synthesis
        // that reshuffles between openings reads as guesswork.
        let first = SynthesisClustering.clusters(from: entries).map(\.theme)
        for _ in 0..<8 {
            XCTAssertEqual(SynthesisClustering.clusters(from: entries).map(\.theme), first)
        }
    }

    // MARK: - Arc

    func testArcNeedsTwoFullDisjointSlices() {
        let five = (0..<5).map { entry(day: $0, themes: ["work"]) }
        XCTAssertNil(SynthesisClustering.arc(from: five), "five entries cannot give two slices of three")

        let six = (0..<6).map { entry(day: $0, themes: ["work"]) }
        XCTAssertNotNil(SynthesisClustering.arc(from: six))
    }

    func testArcSlicesDoNotOverlap() {
        let entries = (0..<6).map { entry(day: $0, themes: ["work"]) }
        let arc = try! XCTUnwrap(SynthesisClustering.arc(from: entries))
        let early = Set(arc.early.map(\.id))
        let late = Set(arc.late.map(\.id))
        XCTAssertTrue(early.isDisjoint(with: late))
        XCTAssertEqual(early.count, 3)
        XCTAssertEqual(late.count, 3)
    }

    func testArcEarlySliceIsOldest() {
        let entries = (0..<6).map { entry(day: $0, themes: ["work"]) }
        let arc = try! XCTUnwrap(SynthesisClustering.arc(from: entries))
        // day: 5 is the furthest back, so it opens the early slice.
        XCTAssertEqual(arc.early.first?.id, entries[5].id)
        // The late slice is newest-first.
        XCTAssertEqual(arc.late.first?.id, entries[0].id)
    }

    // MARK: - Output guard

    func testGuardRejectsTheGenericPhrasingTheModelActuallyProduced() {
        // Verbatim from a real run against a month of entries, on a prompt
        // that explicitly forbade the word "balance".
        XCTAssertEqual(SynthesisGuard.rejection(for: "Work-life imbalance"), .generic)
        XCTAssertEqual(SynthesisGuard.rejection(for: "You are struggling with work life balance."), .generic)
        XCTAssertEqual(SynthesisGuard.rejection(for: "Your emotional journey continues."), .generic)
    }

    func testGuardRejectsAdviceHoweverGentlyPhrased() {
        let advisory = [
            "What strategies can you implement to better manage your workload?",
            "You should leave the office earlier.",
            "Try to call your mother more often.",
            "Consider setting a boundary at work.",
            "It's important to rest after a long week.",
        ]
        for text in advisory {
            XCTAssertEqual(SynthesisGuard.rejection(for: text), .advisory, "should reject: \(text)")
        }
    }

    func testGuardRejectsAnythingClinical() {
        let clinical = [
            "This reads like depression.",
            "You may have an anxiety disorder.",
            "These are symptoms worth taking to a therapist.",
        ]
        for text in clinical {
            XCTAssertEqual(SynthesisGuard.rejection(for: text), .clinical, "should reject: \(text)")
        }
    }

    func testGuardRejectsBareLabelsAndPadding() {
        XCTAssertEqual(SynthesisGuard.rejection(for: "Work"), .tooShort)
        XCTAssertEqual(SynthesisGuard.rejection(for: "Procrastination"), .notASentence)
        XCTAssertEqual(SynthesisGuard.rejection(for: String(repeating: "long ", count: 60)), .tooLong)
    }

    func testGuardAcceptsTheSpecificObservationsWeWant() {
        // The first is verbatim real output from the map-reduce path.
        let good = [
            "You stay late when the flat is empty.",
            "You rehearse conversations with Dan that end up lasting ten minutes.",
            "The evenings you skip the gym are the evenings you had already decided to work.",
        ]
        for text in good {
            XCTAssertNil(SynthesisGuard.rejection(for: text), "should accept: \(text)")
            XCTAssertTrue(SynthesisGuard.accepts(text))
        }
    }

    // MARK: - Fallback sentence

    func testFallbackStatesOnlyTheArithmetic() {
        let entries = (0..<4).map { entry(day: $0, themes: ["money"], valence: -0.5) }
        let cluster = try! XCTUnwrap(SynthesisClustering.clusters(from: entries).first)
        let sentence = SynthesisGuard.fallbackSentence(for: cluster, totalEntries: 12)

        XCTAssertTrue(sentence.contains("4 of your 12 entries"), sentence)
        // The fallback must itself survive the guard, or a model failure would
        // put rejected copy on screen.
        XCTAssertNil(SynthesisGuard.rejection(for: sentence), sentence)
    }

    func testFallbackMentionsDirectionOnlyWhenTheDeltaIsRealbut() {
        // Delta 0 -> no claim about direction at all.
        let flat = (0..<3).map { entry(day: $0, themes: ["routine"], valence: 0.1) }
        let flatCluster = try! XCTUnwrap(SynthesisClustering.clusters(from: flat).first)
        let flatSentence = SynthesisGuard.fallbackSentence(for: flatCluster, totalEntries: 3)
        XCTAssertFalse(flatSentence.contains("lower"))
        XCTAssertFalse(flatSentence.contains("brighter"))

        // A real negative delta -> says "lower".
        let mixed = [
            entry(day: 0, themes: ["money"], valence: -0.7),
            entry(day: 1, themes: ["money"], valence: -0.7),
            entry(day: 2, themes: ["money"], valence: -0.7),
            entry(day: 3, themes: ["friends"], valence: 0.7),
            entry(day: 4, themes: ["friends"], valence: 0.7),
            entry(day: 5, themes: ["friends"], valence: 0.7),
        ]
        let money = try! XCTUnwrap(SynthesisClustering.clusters(from: mixed).first { $0.theme == "money" })
        XCTAssertTrue(SynthesisGuard.fallbackSentence(for: money, totalEntries: 6).contains("lower"))
    }

    // MARK: - Cache key

    func testFingerprintChangesWhenAnEntryIsReanalysed() {
        let original = entry(day: 0, themes: ["work"], valence: -0.2, emotion: "Anxious")
        let reanalysed = SynthesisEntry(
            id: original.id,
            date: original.date,
            transcript: original.transcript,
            primaryEmotion: "Calm",
            themes: ["work"],
            valence: 0.4,
            intensity: original.intensity
        )
        XCTAssertNotEqual(
            SynthesisStore.fingerprint(periodLabel: "Month", entries: [original]),
            SynthesisStore.fingerprint(periodLabel: "Month", entries: [reanalysed]),
            "re-analysing an entry must invalidate the cached synthesis"
        )
    }

    func testFingerprintIsStableForTheSameEntriesInAnyOrder() {
        let a = entry(day: 0, themes: ["work"])
        let b = entry(day: 1, themes: ["sleep"])
        XCTAssertEqual(
            SynthesisStore.fingerprint(periodLabel: "Month", entries: [a, b]),
            SynthesisStore.fingerprint(periodLabel: "Month", entries: [b, a])
        )
    }

    func testFingerprintDistinguishesPeriods() {
        let entries = [entry(day: 0, themes: ["work"])]
        XCTAssertNotEqual(
            SynthesisStore.fingerprint(periodLabel: "Week", entries: entries),
            SynthesisStore.fingerprint(periodLabel: "Month", entries: entries)
        )
    }
}
