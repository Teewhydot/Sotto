import Foundation
import FoundationModels

/// The shape the model must return. At file scope rather than nested in the
/// actor: `@Generable` expands into code that refers to the type from outside
/// its own scope, so a private nested type is inaccessible to its own macro.
@Generable
private struct EntryInsight {
    @Guide(description: "A neutral one or two sentence summary of what the writer described.")
    var summary: String

    @Guide(description: "The dominant feeling as a single capitalised word, for example Reflective, Anxious, Restless.")
    var primaryEmotion: String

    @Guide(description: "How strongly that feeling comes through.", .range(1...10))
    var intensity: Int

    @Guide(description: "The writer's apparent energy, where 1 is depleted and 10 is energised.", .range(1...10))
    var energyLevel: Int

    @Guide(description: "Emotional tone from -1.0 for wholly negative to 1.0 for wholly positive.")
    var valence: Double

    @Guide(description: "Three short lowercase topic words, each a single word where possible.", .count(3))
    var themes: [String]

    @Guide(description: """
        One open question inviting the writer to reflect further, addressed \
        to them as "you". Do not give advice or suggest what they should do.
        """)
    var followUpQuestion: String

    @Guide(description: """
        One gentle observation about something the writer hinted at without \
        saying outright, addressed to them as "you". Never diagnose, never \
        name a condition, never advise.
        """)
    var hiddenObservation: String
}


/// Per-entry analysis and live transcript cleanup on Apple's built-in
/// on-device model.
///
/// This replaces the MLX path on any device with Apple Intelligence, and the
/// difference is not only model size (~3B against the 1B we shipped):
///
/// - **Nothing is downloaded.** The model is already on the device, so the
///   700 MB fetch, the Hugging Face bridges, the progress plumbing and the
///   whole "remove model" surface stop applying.
/// - **Structured output is guaranteed.** `@Generable` with `@Guide`
///   constraints is enforced during decoding, so `parseInsightJSON` — the
///   fence-stripping, the brace-hunting, the range clamping — has nothing
///   left to defend against on this path.
/// - **It runs in the Simulator**, which MLX cannot, because MLX needs a
///   Metal GPU family the Simulator does not provide.
///
/// `LocalInsightEngine` stays as the fallback for devices without Apple
/// Intelligence. See `InsightEngines` for how one is chosen.
///
/// An actor, not a `@MainActor` type: `respond` is `nonisolated(nonsending)`
/// and inherits its caller's isolation, so calling it from the main actor
/// would run generation on the main thread.
actor FoundationInsightEngine {
    static let shared = FoundationInsightEngine()

    private init() {}

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: Per-entry analysis

    private static let analysisInstructions = """
        You reflect a person's private journal entry back to them, speaking to \
        them directly as "you". Be warm, plain and specific.

        Hard rules:
        - Never diagnose, never name a medical or psychological condition, and \
        never imply one.
        - Never give advice, instructions or strategies.
        - Only describe what this entry actually contains. Do not invent detail.
        """

    func analyze(_ transcript: String) async throws -> AnalysisResult {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw InsightEngineError.emptyTranscript
        }

        let session = LanguageModelSession(instructions: Self.analysisInstructions)
        let insight = try await session.respond(
            to: "Reflect on this journal entry.\n\n\(text)",
            generating: EntryInsight.self,
            options: GenerationOptions(temperature: 0.3)
        ).content

        // `.range` is enforced during decoding, so intensity and energy arrive
        // in bounds. Valence has no integer guide to hang a range on, and the
        // observation fields can still carry advice the schema cannot see, so
        // both are checked here rather than trusted.
        return AnalysisResult(
            summary: insight.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryEmotion: insight.primaryEmotion
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .capitalizedFirst,
            intensity: min(max(insight.intensity, 1), 10),
            energyLevel: min(max(insight.energyLevel, 1), 10),
            valence: min(max(insight.valence, -1), 1),
            // Deduplicated because normalising can collapse two distinct
            // model outputs onto one word, and the theme chips are rendered
            // with `ForEach(..., id: \.self)` — duplicate ids there give
            // undefined layout.
            themes: Self.deduplicated(insight.themes),
            followUpQuestion: Self.sanitise(insight.followUpQuestion),
            hiddenObservation: Self.sanitise(insight.hiddenObservation)
        )
    }

    /// Normalises themes and drops repeats, preserving order.
    ///
    /// Normalising can collapse two distinct model outputs onto the same word,
    /// and the theme chips render with `ForEach(..., id: \.self)` — duplicate
    /// ids there give undefined layout.
    private static func deduplicated(_ themes: [String]) -> [String] {
        var seen = Set<String>()
        return themes
            .map { SynthesisClustering.normalise($0) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Drops free-text output that reads as advice or diagnosis.
    ///
    /// Guided generation constrains shape, not content: in testing this model
    /// returned "What strategies can the writer implement to better manage
    /// their workload" for a field whose instructions forbade advice. An empty
    /// string is better than that — the UI already hides these when blank.
    private static func sanitise(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SynthesisGuard.accepts(trimmed) ? trimmed : ""
    }

    // MARK: Live transcript cleanup

    private static let cleaningInstructions = """
        You repair speech-to-text output. Fix punctuation, capitalisation and \
        obvious transcription errors, and remove filler words like "um" and \
        "uh".

        You must not paraphrase, summarise, shorten, translate, censor or \
        reorder anything. Keep the speaker's own words and their meaning \
        exactly. Reply with the corrected text and nothing else.
        """

    func clean(_ transcript: String) async throws -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        let session = LanguageModelSession(instructions: Self.cleaningInstructions)
        let cleaned = try await session.respond(
            to: text,
            options: GenerationOptions(sampling: .greedy, temperature: 0)
        ).content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cleanup must never lose the speaker's content. A result that
        // collapsed to a fraction of the input means the model summarised
        // instead of repairing, so the raw transcript is kept — a rough
        // transcript is recoverable, a silently truncated one is not.
        guard !cleaned.isEmpty, cleaned.count >= text.count / 2 else {
            return text
        }
        return cleaned
    }
}
