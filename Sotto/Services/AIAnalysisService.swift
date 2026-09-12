import Foundation

// MARK: - Analysis result (persisted by callers)
struct AnalysisResult: Codable, Equatable {
    let summary: String
    let primaryEmotion: String
    let intensity: Int
    let energyLevel: Int
    let valence: Double
    let themes: [String]
    let followUpQuestion: String
    let hiddenObservation: String
}

// MARK: - Service
/// Runs insight analysis entirely on-device. The transcript never leaves the device.
///
/// Strategy:
/// 1. Primary — whichever on-device model this hardware can run, chosen by
///    `InsightEngines`: Apple's built-in model where Apple Intelligence is
///    available (nothing to download), else the MLX model.
/// 2. Fallback — deterministic NaturalLanguage heuristics (`NLInsightEngine`)
///    so every entry gets insights immediately, even on the very first use or
///    if the model fails.
@Observable
final class AIAnalysisService {
    var state: ViewState<AnalysisResult> = .initial

    /// 0–1 while a model downloads in the background; nil otherwise. Stays nil
    /// for the whole session on Apple Intelligence, which has nothing to fetch.
    var modelDownloadProgress: Float?

    private let engines = InsightEngines.shared
    private var preparationStarted = false

    func analyzeTranscript(_ text: String) async {
        state = .loading

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error(.aiAnalysisFailed("Transcript is empty."))
            return
        }

        // Primary — the on-device model, once it can run.
        engines.refresh()
        if await engines.isReady() {
            do {
                state = .loaded(try await engines.analyze(text))
                return
            } catch {
                // Fall through to heuristics rather than failing the entry —
                // losing the entry would be far worse than a plainer insight.
                print("AIAnalysisService: \(engines.backend) analysis failed, using heuristics — \(error)")

                // Say so once. Silently serving weaker insights for the rest
                // of the session is the behaviour that made a broken model
                // indistinguishable from a working one.
                if engines.didFallBackFromAppleIntelligence {
                    FeedbackCenter.shared.infoOnce(
                        "insight-engine-degraded",
                        "Using simpler insights",
                        detail: "The on-device language model isn't responding, so entries are analysed with built-in heuristics for now."
                    )
                }
            }
        }

        // Fallback — instant deterministic insights.
        state = .loaded(NLInsightEngine.analyze(transcript: text))

        // Upgrade path — quietly fetch the LLM for future entries.
        startBackgroundPreparation()
    }

    private func startBackgroundPreparation() {
        guard !preparationStarted else { return }
        // Nothing to fetch on Apple Intelligence, and nowhere to fetch it to
        // when no engine can run — either way, starting a download would be
        // pure waste.
        guard engines.requiresDownload else { return }
        preparationStarted = true

        Task { [engines] in
            do {
                try await engines.prepare { fraction, _ in
                    let captured = fraction
                    Task { @MainActor in
                        self.modelDownloadProgress = captured
                    }
                }
                await MainActor.run {
                    self.modelDownloadProgress = nil
                }
            } catch {
                // Allow a retry attempt on the next analysis.
                await MainActor.run {
                    self.modelDownloadProgress = nil
                    self.preparationStarted = false
                }
            }
        }
    }

    /// Tolerant JSON extraction: strips markdown fences and any prose the
    /// model adds around the object.
    static func parseInsightJSON(_ text: String) -> AnalysisResult? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = String(trimmed.dropFirst(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("json") { trimmed = String(trimmed.dropFirst(4)) }
            if let end = trimmed.range(of: "```") { trimmed = String(trimmed[..<end.lowerBound]) }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        let json = String(trimmed[start...end])
        guard let result = try? JSONDecoder().decode(AnalysisResult.self, from: Data(json.utf8)) else {
            return nil
        }
        // The model is asked for 1-10 / -1...1 ranges but isn't guaranteed to
        // honor them — clamp so a wild value can't reach gauges/progress bars
        // built assuming the documented range.
        return AnalysisResult(
            summary: result.summary,
            primaryEmotion: result.primaryEmotion,
            intensity: min(max(result.intensity, 1), 10),
            energyLevel: min(max(result.energyLevel, 1), 10),
            valence: min(max(result.valence, -1.0), 1.0),
            themes: result.themes,
            followUpQuestion: result.followUpQuestion,
            hiddenObservation: result.hiddenObservation
        )
    }
}
