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
    case simulatorUnsupported
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .notPrepared: "Local insight model is not loaded."
        case .missingTokenizerConfig: "Tokenizer config missing from downloaded model."
        case .unparseableOutput: "Model output was not valid insight JSON."
        case .timedOut: "Local model took too long to respond."
        case .simulatorUnsupported: "Smart Insights needs a real device — MLX requires direct Metal GPU access, which the iOS Simulator doesn't provide."
        case .premiumRequired: "Smart Insights is a premium feature."
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

    /// Count of `analyze`/`clean` calls currently mid-generation. `unload()`
    /// dropping `container` doesn't stop an already-running call — it
    /// captured its own `ModelContainer`/`ChatSession` locally before the
    /// guard, so the in-flight generation keeps reading the model's weights
    /// and tokenizer/template files straight off disk. Deleting those files
    /// out from under it (Settings → Remove Model, right after finishing an
    /// entry) is what was crashing the app; `waitForIdle()` closes that gap.
    private var activeGenerations = 0

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

        #if targetEnvironment(simulator)
        // MLX requires a modern Metal MTLGPUFamily that the iOS Simulator
        // does not provide (confirmed in mlx-swift's own "Running on iOS"
        // docs) — attempting to load weights here doesn't throw a catchable
        // Swift error, it hard-aborts the process from inside MLX's C++
        // core. Failing fast with a normal error instead lets the existing
        // setup-screen/Settings error UI explain it, with a Retry that's
        // honest about needing a real device (or the "Mac (Designed for
        // iPad)" run destination, which does have Metal access).
        throw InsightEngineError.simulatorUnsupported
        #endif

        // Single choke point for the premium gate: every path that can start
        // a download/load funnels through here, including the two silent
        // background warm-ups in SpeechService/AIAnalysisService that never
        // touch ModelLibrary or any UI at all. Gating only at the UI layer
        // (hiding the Download button) would miss those entirely.
        guard await PremiumManager.shared.isSmartInsightsUnlocked else {
            throw InsightEngineError.premiumRequired
        }

        let observerID = UUID()
        progressObservers[observerID] = progressHandler
        defer { progressObservers.removeValue(forKey: observerID) }

        if let running = preparationTask {
            try await running.value
            return
        }

        let task = Task { [weak self] () throws -> Void in
            guard let self else { return }
            // A prior crash (or any interruption) mid-write can leave a
            // truncated file on disk that HubApi's own etag-based caching
            // will still treat as "already downloaded" on retry, since that
            // check only re-verifies content hash for large LFS files, not
            // small JSON configs. Loading a truncated config/weights file is
            // exactly what was crashing MLX's C++ loader with a native
            // nullptr abort — one Swift can't catch — right after the
            // snapshot reported 100%. Discarding anything that doesn't look
            // structurally sound forces a guaranteed-clean re-download.
            Self.discardSnapshotIfCorrupted()

            // Coalesce like the Whisper download does — without this, every
            // raw URLSession progress tick (many per second) spawned its own
            // actor hop + MainActor hop, which is what made this download
            // feel noticeably jankier than Whisper's.
            var lastReportedFraction: Float = -1
            let loaded = try await loadModelContainer(
                from: HFDownloader(),
                using: HFTokenizerLoader(),
                configuration: ModelConfiguration(id: Self.modelID),
                progressHandler: { progress in
                    let fraction = Float(progress.fractionCompleted)
                    guard fraction - lastReportedFraction >= 0.002 || fraction >= 1 else { return }
                    lastReportedFraction = fraction
                    let speed = progress.userInfo[.throughputKey] as? Double
                    Task { await self.broadcastProgress(fraction, speed) }
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

    /// Deletes the on-disk snapshot if it exists but doesn't look complete —
    /// missing/empty required files, or a config that isn't valid JSON. Safe
    /// to call unconditionally before every download attempt: a healthy
    /// snapshot is left untouched (HubApi's own etag check then skips
    /// re-downloading anything unchanged), and only a corrupted one pays the
    /// cost of a fresh download.
    private static func discardSnapshotIfCorrupted() {
        let fm = FileManager.default
        let dir = ModelLibrary.insightDownloadBase
            .appendingPathComponent("models")
            .appendingPathComponent(modelID)
        guard fm.fileExists(atPath: dir.path) else { return }

        func isNonEmptyFile(_ name: String) -> Bool {
            let path = dir.appendingPathComponent(name).path
            guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int else { return false }
            return size > 0
        }
        func isValidJSON(_ name: String) -> Bool {
            let path = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: path) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        }

        // tokenizer.json is required by every load; config.json drives the
        // model architecture. Both must exist, be non-empty, and parse.
        let requiredJSON = ["config.json", "tokenizer.json"]
        let sound = requiredJSON.allSatisfy { isNonEmptyFile($0) && isValidJSON($0) }
            // At least one real weights file, and not a stub-sized truncation.
            && ((try? fm.contentsOfDirectory(atPath: dir.path))?.contains { name in
                name.hasSuffix(".safetensors") &&
                ((try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.size] as? Int ?? 0) > 1_000_000
            } ?? false)

        if !sound {
            try? fm.removeItem(at: dir)
        }
    }

    /// Releases the in-memory model (used when the user deletes it in
    /// Settings). A pending download is cancelled; it can be re-run later.
    /// This alone does NOT make it safe to delete the model's files —
    /// see `waitForIdle()`.
    func unload() {
        preparationTask?.cancel()
        preparationTask = nil
        container = nil
    }

    /// Waits for any `analyze`/`clean` call already past the `container`
    /// guard to finish. Call this — after `unload()` — before deleting the
    /// model's files on disk: `unload()` only stops *new* calls from
    /// starting; a call already mid-generation is unaffected by it and may
    /// still be reading weights/tokenizer files straight off disk.
    func waitForIdle() async {
        while activeGenerations > 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
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
        activeGenerations += 1
        defer { activeGenerations -= 1 }

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
        activeGenerations += 1
        defer { activeGenerations -= 1 }

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
