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
/// 1. Primary — a small LLM run locally with MLX (see `LocalInsightEngine`).
///    Downloaded once in the background after the first analysis.
/// 2. Fallback — deterministic NaturalLanguage heuristics (`NLInsightEngine`)
///    so every entry gets insights immediately, even on the very first use or
///    if the local model fails.
@Observable
final class AIAnalysisService {
    var state: ViewState<AnalysisResult> = .initial

    /// 0–1 while the local LLM downloads in the background; nil otherwise.
    var modelDownloadProgress: Float?

    private let localEngine = LocalInsightEngine.shared
    private var preparationStarted = false

    func analyzeTranscript(_ text: String) async {
        state = .loading

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error(.aiAnalysisFailed("Transcript is empty."))
            return
        }

        // Primary — local LLM once prepared.
        if await localEngine.isReady() {
            do {
                state = .loaded(try await localEngine.analyze(text))
                return
            } catch {
                // Fall through to heuristics rather than failing the entry.
            }
        }

        // Fallback — instant deterministic insights.
        state = .loaded(NLInsightEngine.analyze(transcript: text))

        // Upgrade path — quietly fetch the LLM for future entries.
        startBackgroundPreparation()
    }

    private func startBackgroundPreparation() {
        guard !preparationStarted else { return }
        preparationStarted = true

        Task { [localEngine] in
            do {
                try await localEngine.prepare { fraction in
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
        return try? JSONDecoder().decode(AnalysisResult.self, from: Data(json.utf8))
    }
}
