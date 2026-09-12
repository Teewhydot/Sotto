import Foundation
import FoundationModels

// MARK: - Generated shapes

/// One cluster's name. The model receives the entries and returns only the
/// wording — no dates it could invent, because `clearestDate` is checked
/// against the cluster before it reaches the UI.
@Generable
private struct GeneratedPattern {
    @Guide(description: """
        The pattern in one plain sentence addressed to the writer as "you". \
        Name the specific trigger and the specific behaviour. Never use the \
        words balance, wellbeing, self-care, struggle, or journey. Do not \
        give advice.
        """)
    var sentence: String

    @Guide(description: "The date, copied exactly from the entries above, that shows this most clearly.")
    var clearestDate: String

    @Guide(description: "How confident you are that this is a real pattern rather than coincidence.",
           .anyOf(["tentative", "likely", "strong"]))
    var confidence: String
}

@Generable
private struct GeneratedArc {
    @Guide(description: """
        What is concretely different between the earlier entries and the \
        recent ones, in one sentence addressed to the writer as "you". \
        Describe what changed. Do not give advice or suggest strategies.
        """)
    var sentence: String

    @Guide(description: "The date, copied exactly from the entries above, where the change becomes visible.")
    var turningPointDate: String
}

@Generable
private struct GeneratedQuestion {
    @Guide(description: """
        One open question drawn from the entries themselves, addressed to the \
        writer as "you", worth sitting with. It must not suggest a course of \
        action, recommend anything, or contain the word "strategies".
        """)
    var question: String
}

// MARK: - Synthesizer

/// The reduce half of synthesis: turns clusters chosen by `SynthesisClustering`
/// into sentences, using Apple's on-device model.
///
/// An actor rather than a `@MainActor` type on purpose. `respond` is declared
/// `nonisolated(nonsending)`, so it runs on whatever actor calls it — calling
/// it from the main actor would put a multi-second generation on the main
/// thread.
///
/// Requests run one at a time. `LanguageModelSession` reports a
/// `concurrentRequests` error rather than queueing, and a monthly synthesis
/// is cached anyway, so serial execution costs nothing a user can feel.
actor FoundationSynthesizer {
    static let shared = FoundationSynthesizer()

    private init() {}

    /// Whether the framework can run here at all. Checked before the paywall
    /// is ever shown — see `InsightEngineAvailability`.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Long transcripts are truncated before they reach a prompt. Six entries
    /// of unbounded voice transcript is the reliable way to hit
    /// `exceededContextWindowSize`.
    private static let transcriptBudget = 480

    private static let instructions = """
        You describe patterns in a person's own private journal entries, \
        speaking to them directly as "you".

        Hard rules:
        - Only claim what the entries in front of you actually show.
        - Never diagnose, never name a medical or psychological condition, \
        never imply one.
        - Never give advice, instructions, or strategies. Describe what \
        happened and what recurs. That is all.
        - Be concrete. "You stay late when the flat is empty" is right; \
        "you have difficulty with work-life balance" is wrong and useless.
        - Never invent a date. Only copy dates shown to you.
        """

    // MARK: Entry point

    /// Runs the full synthesis. Returns nil when there is not enough to say.
    ///
    /// Never throws: a synthesis is a nice-to-have on a screen that already
    /// works, so a model failure degrades to arithmetic rather than an error.
    func synthesise(
        entries: [SynthesisEntry],
        periodLabel: String
    ) async -> JournalSynthesis? {
        guard Self.isAvailable else { return nil }

        let clusters = SynthesisClustering.clusters(from: entries)
        guard !clusters.isEmpty else { return nil }

        var patterns: [SynthesisPattern] = []
        for cluster in clusters {
            patterns.append(await name(cluster, totalEntries: entries.count))
        }

        let arc = await describeArc(for: entries)
        let question = await askQuestion(about: clusters[0])

        return JournalSynthesis(
            periodLabel: periodLabel,
            entryCount: entries.count,
            patterns: patterns,
            arc: arc,
            question: question,
            generatedAt: Date()
        )
    }

    // MARK: Patterns

    private func name(_ cluster: ThemeCluster, totalEntries: Int) async -> SynthesisPattern {
        let generated = await generate(GeneratedPattern.self, temperature: 0.3) {
            """
            These \(cluster.entries.count) entries were grouped together \
            automatically because they all mention "\(cluster.theme)". \
            Name the pattern they share.

            \(Self.render(cluster.entries))
            """
        }

        // Evidence is the cluster, always. Only wording came from the model,
        // and only if it survived the guard.
        let sentence: String
        var confidence: SynthesisPattern.Confidence

        if let generated, SynthesisGuard.accepts(generated.sentence) {
            sentence = generated.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            confidence = SynthesisPattern.Confidence(rawValue: generated.confidence) ?? .likely
        } else {
            sentence = SynthesisGuard.fallbackSentence(for: cluster, totalEntries: totalEntries)
            // The fallback is a count, not an interpretation, so it does not
            // get to claim more than "tentative".
            confidence = .tentative
        }

        // Support caps confidence regardless of what the model said. Three
        // entries is the floor for calling something a pattern at all; it is
        // not enough to call it strong.
        if cluster.support < 4, confidence == .strong { confidence = .likely }

        let clearest = generated
            .flatMap { Self.matchEntry(dateString: $0.clearestDate, in: cluster.entries) }
            ?? cluster.mostVividEntry
            ?? cluster.entries[0]

        return SynthesisPattern(
            theme: cluster.theme,
            sentence: sentence,
            confidence: confidence,
            evidence: cluster.entries,
            support: cluster.support,
            clearestEntryID: clearest.id,
            readsWorseThanUsual: cluster.valenceDelta < -0.1
        )
    }

    // MARK: Arc

    private func describeArc(for entries: [SynthesisEntry]) async -> SynthesisArc? {
        guard let slices = SynthesisClustering.arc(from: entries) else { return nil }

        let generated = await generate(GeneratedArc.self, temperature: 0.3) {
            """
            Earlier entries:
            \(Self.render(slices.early))

            Most recent entries:
            \(Self.render(slices.late))

            What is different between them?
            """
        }

        guard let generated, SynthesisGuard.accepts(generated.sentence) else { return nil }

        let pool = slices.early + slices.late
        return SynthesisArc(
            sentence: generated.sentence.trimmingCharacters(in: .whitespacesAndNewlines),
            turningPointEntryID: Self.matchEntry(dateString: generated.turningPointDate, in: pool)?.id
        )
    }

    // MARK: Question

    private func askQuestion(about cluster: ThemeCluster) async -> String? {
        let generated = await generate(GeneratedQuestion.self, temperature: 0.6) {
            """
            Here are entries where "\(cluster.theme)" comes up.

            \(Self.render(cluster.entries))

            Ask one open question about what these entries show.
            """
        }

        guard let generated else { return nil }
        let question = generated.question.trimmingCharacters(in: .whitespacesAndNewlines)
        // A question is the likeliest place for advice to slip back in — in
        // testing it produced "What strategies can the writer implement…"
        // despite being told not to. If it does, show nothing.
        guard SynthesisGuard.accepts(question), question.contains("?") else { return nil }
        return question
    }

    // MARK: Generation plumbing

    /// One session per request, and every failure swallowed.
    ///
    /// A fresh session keeps each cluster independent — a shared transcript
    /// would let the first pattern's wording bleed into the second, and they
    /// are meant to be separate observations.
    private func generate<T: Generable>(
        _ type: T.Type,
        temperature: Double,
        prompt: () -> String
    ) async -> T? {
        let session = LanguageModelSession(instructions: Self.instructions)
        let text = prompt()

        do {
            let response = try await session.respond(
                to: text,
                generating: type,
                options: GenerationOptions(temperature: temperature)
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                // Truncation is budgeted per entry, so this means an unusual
                // number of unusually long entries. Retrying with half the
                // evidence is better than showing nothing.
                return await retryHalved(type, temperature: temperature, prompt: text)
            case .guardrailViolation, .refusal:
                // The writer's own words tripped Apple's safety filter. Not
                // an error to surface: the entry is legitimate and the
                // arithmetic fallback still describes it.
                return nil
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func retryHalved<T: Generable>(
        _ type: T.Type,
        temperature: Double,
        prompt: String
    ) async -> T? {
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 4 else { return nil }
        let shortened = lines.prefix(lines.count / 2).joined(separator: "\n")

        let session = LanguageModelSession(instructions: Self.instructions)
        return try? await session.respond(
            to: shortened,
            generating: type,
            options: GenerationOptions(temperature: temperature)
        ).content
    }

    // MARK: Prompt rendering

    private static let promptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed locale and calendar: the string the model echoes back has to
        // be matchable, and a device in a non-Gregorian locale would produce
        // dates that never parse on the way home.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func render(_ entries: [SynthesisEntry]) -> String {
        entries
            .map { "[\(promptDateFormatter.string(from: $0.date))] \(truncate($0.transcript))" }
            .joined(separator: "\n")
    }

    private static func truncate(_ transcript: String) -> String {
        let collapsed = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > transcriptBudget else { return collapsed }
        // Cut on a word boundary so the model is not handed a half word.
        let clipped = collapsed.prefix(transcriptBudget)
        let boundary = clipped.lastIndex(of: " ") ?? clipped.endIndex
        return clipped[..<boundary] + "…"
    }

    /// Maps a model-returned date back to a real entry, or nil.
    ///
    /// This is the check that makes citations trustworthy. Asked to work over
    /// a whole month, the model cited two dates that were not in its input at
    /// all; anything unmatched here is discarded rather than displayed.
    private static func matchEntry(dateString: String, in entries: [SynthesisEntry]) -> SynthesisEntry? {
        let wanted = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        return entries.first { promptDateFormatter.string(from: $0.date) == wanted }
    }
}
