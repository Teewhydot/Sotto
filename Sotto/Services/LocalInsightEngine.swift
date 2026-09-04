import Foundation
import Hub
import Tokenizers
import MLXLMCommon

// MARK: - Hugging Face bridges
// mlx-swift-lm 3.x decoupled hub access behind `Downloader` / `TokenizerLoader`
// protocols; its MLXHuggingFace macros target a `HuggingFace` module we don't
// ship, so these small conformances adapt swift-transformers instead.

private struct HFDownloader: Downloader {
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let api = HubApi(downloadBase: ModelLibrary.insightDownloadBase)
        // Cached snapshots are returned without network access; useLatest is
        // intentionally ignored so entries analyze even when offline.
        return try await api.snapshot(
            from: id,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private struct HFTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let configuration = LanguageModelConfigurationFromHub(modelFolder: directory)
        guard let tokenizerConfig = try await configuration.tokenizerConfig else {
            throw InsightEngineError.missingTokenizerConfig
        }
        let tokenizerData = try await configuration.tokenizerData
        let upstream = try AutoTokenizer.from(
            tokenizerConfig: tokenizerConfig,
            tokenizerData: tokenizerData
        )
        return STTokenizerBridge(upstream: upstream)
    }
}

/// Adapts swift-transformers' tokenizer to MLXLMCommon's protocol. The two
/// protocols are shape-compatible, so this is pure pass-through.
private struct STTokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }
}

// MARK: - Engine

enum InsightEngineError: LocalizedError {
    case notPrepared
    case missingTokenizerConfig
    case unparseableOutput
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notPrepared: "Local insight model is not loaded."
        case .missingTokenizerConfig: "Tokenizer config missing from downloaded model."
        case .unparseableOutput: "Model output was not valid insight JSON."
        case .timedOut: "Local model took too long to respond."
        }
    }
}

/// Runs insight analysis and transcript cleanup through a small LLM executed
/// entirely on-device with MLX. The transcript never leaves the device.
///
/// Shared singleton: the loaded container (~700 MB resident) must exist once
/// per process regardless of how many service instances use it.
actor LocalInsightEngine {
    static let shared = LocalInsightEngine()

    private init() {}

    /// ~700 MB 4-bit quantized 1B instruct model — good quality/size balance
    /// for short journal entries on modern iPhones.
    static let modelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    private var container: ModelContainer?
    private var preparationTask: Task<Void, Error>?
    /// Every in-flight caller's progress callback, keyed so each can be
    /// unregistered independently. `preparationTask` is shared across
    /// concurrent/overlapping `prepare()` calls (e.g. a silent background
    /// warm-up from `SpeechService` racing a user-initiated download from
    /// Settings) — without broadcasting to all of them, only whichever
    /// caller happened to start the task would ever see progress, and every
    /// other caller's UI would sit frozen until the download just completed.
    private var progressObservers: [UUID: @Sendable (Float, Double?) -> Void] = [:]

    private static let instructions = """
    You are a warm, empathetic journaling companion. The speaker shares private \
    voice-journal entries and you reflect them back supportively. Stay neutral \
    and kind; never judge, diagnose, or moralize. Follow the requested JSON \
    format exactly.
    """

    private static let jsonPrompt = """
    Reflect on this private voice-journal entry for the person who wrote it.

    Respond with ONLY a JSON object, no other text, matching exactly this shape:
    {
      "summary": "1-2 sentence neutral summary",
      "primaryEmotion": "single word, e.g. Reflective, Anxious, Joyful",
      "intensity": <int 1-10>,
      "energyLevel": <int 1-10>,
      "valence": <double -1.0 to 1.0>,
      "themes": ["three", "short", "lowercase"],
      "followUpQuestion": "open question inviting reflection",
      "hiddenObservation": "gentle observation about a feeling the speaker hinted at"
    }

    Transcript: "%@"
    """

    func isReady() -> Bool {
        container != nil
    }

    /// Downloads (first time only) and loads the model. Safe to call repeatedly
    /// and concurrently — concurrent callers await the in-flight task.
    ///
    /// `progressHandler` receives the fraction complete (weighted by file
    /// count across the snapshot, not by bytes — small config/tokenizer
    /// files can jump the fraction well ahead of the dominant weights file)
    /// and, when available, the current throughput in bytes/sec.
    func prepare(progressHandler: @escaping @Sendable (Float, Double?) -> Void) async throws {
        if container != nil { return }

        let observerID = UUID()
        progressObservers[observerID] = progressHandler
        defer { progressObservers.removeValue(forKey: observerID) }

        if let running = preparationTask {
            try await running.value
            return
        }

        let task = Task { [weak self] () throws -> Void in
            guard let self else { return }
            let loaded = try await loadModelContainer(
                from: HFDownloader(),
                using: HFTokenizerLoader(),
                configuration: ModelConfiguration(id: Self.modelID),
                progressHandler: { progress in
                    let speed = progress.userInfo[.throughputKey] as? Double
                    Task { await self.broadcastProgress(Float(progress.fractionCompleted), speed) }
                }
            )
            await self.store(loaded)
        }
        preparationTask = task
        // Runs even when task.value throws — otherwise a failed attempt
        // leaves preparationTask pointing at the dead task forever, and
        // every later call (Retry included) just replays its cached error
        // via the `if let running = preparationTask` branch above instead
        // of starting a fresh download.
        defer { preparationTask = nil }
        try await task.value
    }

    private func broadcastProgress(_ fraction: Float, _ speed: Double?) {
        for observer in progressObservers.values {
            observer(fraction, speed)
        }
    }

    private func store(_ loaded: ModelContainer) {
        container = loaded
    }

    /// Releases the in-memory model (used when the user deletes it in
    /// Settings). A pending download is cancelled; it can be re-run later.
    func unload() {
        preparationTask?.cancel()
        preparationTask = nil
        container = nil
    }

    /// Wall-clock budget for one generation. Thermal throttling or a
    /// pathological input could otherwise stall `session.respond` forever,
    /// with no user-facing recovery (analysis/cleanup just spin indefinitely).
    /// MLX generation has no cooperative-cancellation hook, so the loser of
    /// this race keeps running in the background — its result is simply
    /// discarded once the deadline wins.
    private static let generationTimeoutSeconds: UInt64 = 25

    private static func withGenerationTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: generationTimeoutSeconds * 1_000_000_000)
                throw InsightEngineError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw InsightEngineError.timedOut }
            return result
        }
    }

    func analyze(_ transcript: String) async throws -> AnalysisResult {
        guard let container else { throw InsightEngineError.notPrepared }

        let response = try await Self.withGenerationTimeout {
            // A fresh session per entry keeps prompts independent and memory flat.
            let session = ChatSession(
                container,
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: 500, temperature: 0.3)
            )
            return try await session.respond(to: String(format: Self.jsonPrompt, transcript))
        }

        guard let result = AIAnalysisService.parseInsightJSON(response) else {
            throw InsightEngineError.unparseableOutput
        }
        return result
    }

    /// Cleans a raw transcript: filler removal, stutter/false-start removal,
    /// punctuation, capitalization, paragraphs and dash lists for enumerations.
    /// Greedy decoding keeps the edit faithful to the spoken words.
    func clean(_ transcript: String) async throws -> String {
        guard let container else { throw InsightEngineError.notPrepared }

        let response = try await Self.withGenerationTimeout {
            let session = ChatSession(
                container,
                instructions: Self.cleaningInstructions,
                generateParameters: GenerateParameters(maxTokens: 900, temperature: 0.0)
            )
            return try await session.respond(to: String(format: Self.cleaningPrompt, transcript))
        }
        return Self.postProcessCleanup(response)
    }

    private static let cleaningInstructions = """
    You are a meticulous editor for voice-journal transcriptions. You preserve \
    the speaker's own words and meaning exactly; you only remove disfluencies \
    and fix formatting.
    """

    private static let cleaningPrompt = """
    Clean up this raw voice-journal transcript.

    Rules:
    - Remove filler words (um, uh, er, "like" and "I mean" when clearly filler) and throat-clearing sounds.
    - Remove stutters, repeated words, and false starts; keep only the version the speaker settled on.
    - Add correct punctuation, capitalization, and paragraph breaks.
    - When the speaker enumerates items, format them as a dash list, each item on its own line.
    - Do not paraphrase, summarize, add, or omit content beyond these rules.

    Return ONLY the cleaned transcript text, nothing else.

    Transcript:
    \"\"\"%@\"
    \"\"\"
    """

    /// Strips wrapping fences/quotes the model may add and tidies whitespace.
    static func postProcessCleanup(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if out.hasPrefix("```") {
            out = out.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if let end = out.range(of: "```") { out = String(out[..<end.lowerBound]) }
        }
        if out.hasPrefix("\"\"\"") && out.hasSuffix("\"\"\""), out.count > 6 {
            out = String(out.dropFirst(3).dropLast(3))
        } else if out.hasPrefix("\"") && out.hasSuffix("\""), out.count > 1 {
            out = String(out.dropFirst().dropLast())
        }

        // Collapse runs of blank lines; trim trailing spaces per line.
        out = out.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
