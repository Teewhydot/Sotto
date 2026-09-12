import Foundation

// MARK: - Input

/// A journal entry reduced to what synthesis needs.
///
/// Deliberately not the SwiftData model: clustering is arithmetic over
/// already-extracted signals, and it has to be testable without a model
/// container or a host app.
struct SynthesisEntry: Sendable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let transcript: String
    let primaryEmotion: String
    let themes: [String]
    /// -1...1
    let valence: Double
    /// 1...10
    let intensity: Int
}

// MARK: - Clusters

/// Entries that share a theme, with how that theme reads against the
/// writer's own baseline rather than against any absolute scale.
nonisolated struct ThemeCluster: Sendable, Equatable {
    let theme: String
    /// Newest first, and capped at `maximumEntriesPerCluster` to bound prompt
    /// size. This is a *sample*, not the whole cluster — read `support` for
    /// how many entries actually carry the theme.
    let entries: [SynthesisEntry]
    let dominantEmotion: String
    /// Mean valence across *all* matching entries minus the period's mean.
    /// Negative means this theme reads worse than the writer's own average.
    let valenceDelta: Double
    /// Every entry carrying the theme, including any beyond the sample.
    ///
    /// Kept separately because `entries.count` is the sample size: a theme in
    /// 9 of 24 entries would otherwise be presented as "6 of your 24 entries",
    /// which quietly understates the evidence for the claim being made.
    let support: Int

    /// Recurrence weighted by how far the theme moves the needle, so
    /// "recurs and costs something" outranks "recurs and is neutral".
    var weight: Double { Double(support) * abs(valenceDelta) }

    /// True when there are more matching entries than the sample shows.
    var hasMoreEvidenceThanShown: Bool { support > entries.count }

    /// The entry a person would recognise the pattern in fastest. Used when
    /// the model's own pick cannot be verified.
    var mostVividEntry: SynthesisEntry? {
        entries.max { lhs, rhs in
            (lhs.intensity, lhs.date) < (rhs.intensity, rhs.date)
        }
    }
}

// MARK: - Clustering

/// The map half of the synthesis. Entirely deterministic.
///
/// This exists because of a measured failure. Handing a month of entries to
/// the on-device model in one prompt produced "Work-life imbalance" — the
/// generic phrasing the prompt explicitly forbade — and cited two dates that
/// were not in the input. Handing it one pre-grouped cluster and asking only
/// for a name produced "You stay late when the flat is empty", with a correct
/// citation, five times faster.
///
/// So the division of labour is: **evidence is chosen here, in code, and only
/// the wording comes from the model.** A pattern can then never rest on an
/// entry the writer did not actually make.
nonisolated enum SynthesisClustering {

    /// Below three entries a theme is a coincidence, not a pattern, and
    /// naming it as one is the fastest way to lose a reader's trust.
    static let minimumSupport = 3

    /// More than three named patterns reads as a horoscope.
    static let maximumClusters = 3

    /// Caps prompt size. The model sees the most recent few; the cluster
    /// still reports its true support so the UI can say "6 of 9 entries".
    static let maximumEntriesPerCluster = 6

    /// Themes carrying no information about this particular person.
    private static let uninformativeThemes: Set<String> = [
        "life", "day", "today", "thoughts", "feelings", "general",
        "reflection", "journal", "self", "misc", "other", "personal",
    ]

    static func clusters(from entries: [SynthesisEntry]) -> [ThemeCluster] {
        guard entries.count >= minimumSupport else { return [] }

        let baseline = entries.map(\.valence).reduce(0, +) / Double(entries.count)

        // Theme -> the entries carrying it. Matching is case- and
        // whitespace-insensitive because themes arrive from a language model
        // and "Work", "work" and " work" are the same theme to a reader.
        var byTheme: [String: [SynthesisEntry]] = [:]
        for entry in entries {
            var seen = Set<String>()
            for raw in entry.themes {
                let key = normalise(raw)
                guard !key.isEmpty,
                      key.count > 2,
                      !uninformativeThemes.contains(key),
                      seen.insert(key).inserted
                else { continue }
                byTheme[key, default: []].append(entry)
            }
        }

        let candidates: [ThemeCluster] = byTheme.compactMap { theme, matching in
            guard matching.count >= minimumSupport else { return nil }

            let sorted = matching.sorted { $0.date > $1.date }
            let mean = sorted.map(\.valence).reduce(0, +) / Double(sorted.count)
            let dominant = Stats.dominant(sorted.map(\.primaryEmotion)) ?? "Mixed"

            return ThemeCluster(
                theme: theme,
                entries: Array(sorted.prefix(maximumEntriesPerCluster)),
                dominantEmotion: dominant,
                valenceDelta: mean - baseline,
                support: sorted.count
            )
        }

        // Ties broken by support then theme, so the same period always
        // produces the same three patterns in the same order. A synthesis
        // that reshuffles on every open reads as guesswork.
        return candidates
            .sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                if lhs.support != rhs.support { return lhs.support > rhs.support }
                return lhs.theme < rhs.theme
            }
            .prefix(maximumClusters)
            .map { $0 }
    }

    /// Oldest and newest slices of the period, for the "what shifted" ask.
    ///
    /// Narrowed on purpose: asked "what changed?" over a whole month the
    /// model summarised the loudest entry and missed the month's actual turn.
    /// Asked to compare three early entries against three late ones, it found
    /// the right one.
    static func arc(
        from entries: [SynthesisEntry],
        sampleSize: Int = 3
    ) -> (early: [SynthesisEntry], late: [SynthesisEntry])? {
        // Both slices must be disjoint and full, or there is no arc to see.
        guard entries.count >= sampleSize * 2 else { return nil }
        let chronological = entries.sorted { $0.date < $1.date }
        return (
            early: Array(chronological.prefix(sampleSize)),
            late: Array(chronological.suffix(sampleSize).reversed())
        )
    }

    static func normalise(_ theme: String) -> String {
        theme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// MARK: - Output

/// A named pattern. `evidence` is never model-supplied — it is the cluster
/// the pattern was generated from, so every claim on screen is tappable
/// through to entries the writer actually wrote.
nonisolated struct SynthesisPattern: Sendable, Equatable, Identifiable {
    enum Confidence: String, Sendable, Codable {
        case tentative, likely, strong
    }

    var id: String { theme }

    let theme: String
    /// One sentence, from the model, having passed `SynthesisGuard`.
    let sentence: String
    let confidence: Confidence
    /// The entries shown and tappable. A sample when `support` exceeds
    /// `SynthesisClustering.maximumEntriesPerCluster`.
    let evidence: [SynthesisEntry]
    /// How many entries actually carry this theme. Displayed instead of
    /// `evidence.count`, which is only the sample size.
    let support: Int
    /// The entry to open first. Verified against `evidence`.
    let clearestEntryID: UUID
    /// True when this theme reads worse than the writer's own baseline.
    let readsWorseThanUsual: Bool
}

struct SynthesisArc: Sendable, Equatable {
    let sentence: String
    /// Verified against the entries handed to the model.
    let turningPointEntryID: UUID?
}

struct JournalSynthesis: Sendable, Equatable {
    let periodLabel: String
    let entryCount: Int
    let patterns: [SynthesisPattern]
    let arc: SynthesisArc?
    /// A question drawn from the entries, or nil when nothing survived the guard.
    let question: String?
    let generatedAt: Date
}

// MARK: - Output guard

/// Rejects model output that is generic, advisory, or clinical.
///
/// Every rule here corresponds to something the on-device model actually did
/// during testing, not to a hypothetical. Guided generation constrains shape,
/// not content: asked for a pattern and explicitly told to avoid the word
/// "balance", it returned "Work-life imbalance"; told never to give advice,
/// its question was "What strategies can the writer implement to better
/// manage their workload". Both passed the schema. So the schema is not the
/// last line of defence — this is.
nonisolated enum SynthesisGuard {

    /// Phrasing that could describe any person who has ever kept a journal.
    /// A pattern that survives this has to say something about *this* writer.
    static let genericPhrases = [
        "work-life balance", "work life balance", "work-life imbalance",
        "self-care", "self care", "wellbeing", "well-being",
        "mental health", "personal growth", "inner journey",
        "emotional journey", "ups and downs", "mixed emotions",
    ]

    /// Advice, however gently phrased. Sotto reflects; it does not coach.
    static let advisoryPhrases = [
        "you should", "you could try", "try to", "consider ",
        "strategies", "strategy", "tips", "make sure",
        "it's important to", "it is important to", "remember to",
        "i recommend", "we recommend", "recommendation",
        "start by", "focus on", "aim to", "needs to",
    ]

    /// Anything that reads as a diagnosis. A journal must never imply one,
    /// and App Review treats the difference between reflection and clinical
    /// assessment as the line between a lifestyle app and a medical one.
    static let clinicalPhrases = [
        "depression", "depressive", "anxiety disorder", "adhd",
        "burnout syndrome", "ptsd", "ocd", "bipolar", "disorder",
        "symptom", "diagnos", "condition", "therapy", "therapist",
        "you suffer", "suffering from", "clinical",
    ]

    enum Rejection: String, Sendable {
        case tooShort
        case tooLong
        case generic
        case advisory
        case clinical
        case notASentence
    }

    /// Nil when the text is usable.
    static func rejection(for text: String) -> Rejection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if trimmed.count < 12 { return .tooShort }
        // Two sentences of hedging is the model padding. One claim per pattern.
        if trimmed.count > 220 { return .tooLong }
        if genericPhrases.contains(where: lower.contains) { return .generic }
        if advisoryPhrases.contains(where: lower.contains) { return .advisory }
        if clinicalPhrases.contains(where: lower.contains) { return .clinical }
        // A bare label ("Work-life imbalance") rather than an observation.
        if !trimmed.contains(" ") { return .notASentence }

        return nil
    }

    static func accepts(_ text: String) -> Bool {
        rejection(for: text) == nil
    }

    /// What to show when the model cannot produce an acceptable sentence.
    ///
    /// Deliberately plain arithmetic rather than a second generation attempt:
    /// it is always true, it names the writer's own theme, and it never
    /// claims more than the count behind it. A quiet, correct sentence beats
    /// a confident, generic one.
    static func fallbackSentence(for cluster: ThemeCluster, totalEntries: Int) -> String {
        let noun = cluster.support == 1 ? "entry" : "entries"
        let base = "\(cluster.theme.capitalizedFirst) comes up in \(cluster.support) of your \(totalEntries) \(totalEntries == 1 ? "entry" : "entries")"
        guard abs(cluster.valenceDelta) >= 0.15 else {
            return base + "."
        }
        let direction = cluster.valenceDelta < 0 ? "lower" : "brighter"
        return base + ", and those \(noun) read \(direction) than your average."
    }
}

extension String {
    nonisolated var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
