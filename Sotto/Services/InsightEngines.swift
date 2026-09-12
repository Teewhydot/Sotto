import Foundation
import FoundationModels

/// Which on-device model is doing the work.
enum InsightBackend: Equatable, Sendable {
    /// Apple's built-in model. Nothing to download, runs in the Simulator.
    case appleIntelligence
    /// The bundled MLX path, for devices without Apple Intelligence.
    /// Requires a one-time ~700 MB download and a real device.
    case downloadedModel
    /// Neither can run here. Entries still get deterministic insights from
    /// `NLInsightEngine`; Smart Insights is not offered or charged for.
    case unavailable(InsightUnavailableReason)
}

enum InsightUnavailableReason: Equatable, Sendable {
    /// The user can fix this in Settings, so we say so instead of starting a
    /// 700 MB download on their behalf.
    case appleIntelligenceOff
    /// Apple is still fetching its own model. Transient — worth waiting for
    /// rather than downloading ours on top of it.
    case appleIntelligencePreparing
    /// Hardware cannot run either engine (no Apple Intelligence, and MLX
    /// needs Metal that the Simulator does not expose).
    case noEngineOnThisDevice

    var headline: String {
        switch self {
        case .appleIntelligenceOff: "Apple Intelligence is turned off"
        case .appleIntelligencePreparing: "Apple Intelligence is still setting up"
        case .noEngineOnThisDevice: "Not available on this device"
        }
    }

    var detail: String {
        switch self {
        case .appleIntelligenceOff:
            "Smart Insights uses the language model built into your iPhone. Turn on Apple Intelligence in Settings and it will work with nothing to download."
        case .appleIntelligencePreparing:
            "Your iPhone is still downloading its language model. This finishes on its own, usually over Wi-Fi — check back shortly."
        case .noEngineOnThisDevice:
            "Smart Insights needs Apple Intelligence, or a device that can run the downloadable model. Your entries still get insights without it."
        }
    }
}

/// Chooses an insight engine and routes work to it.
///
/// The rules are deliberately not "try Apple, else download":
///
/// - Apple Intelligence **available** → use it. No download, and it works in
///   the Simulator, which the MLX path never could.
/// - Apple Intelligence **switched off** → say so. Downloading 700 MB behind
///   the back of someone who could flip a switch is the wrong trade.
/// - Apple Intelligence **still preparing** → wait. Its download is already
///   in flight; adding ours would compete for the same Wi-Fi.
/// - **Device not eligible** → the MLX path, which is what it is for.
@MainActor
@Observable
final class InsightEngines {
    static let shared = InsightEngines()

    private init() {
        backend = Self.resolve()
    }

    private(set) var backend: InsightBackend

    /// Re-checks availability. Worth calling when a screen that depends on it
    /// appears, since the user can enable Apple Intelligence while the app is
    /// backgrounded and its model can finish preparing at any time.
    func refresh() {
        backend = Self.resolve()
    }

    private static func resolve() -> InsightBackend {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .appleIntelligence

        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceOff)
            case .modelNotReady:
                return .unavailable(.appleIntelligencePreparing)
            case .deviceNotEligible:
                // MLX needs a Metal GPU family the Simulator does not
                // provide, so an ineligible simulator has nowhere left to go.
                #if targetEnvironment(simulator)
                return .unavailable(.noEngineOnThisDevice)
                #else
                return .downloadedModel
                #endif
            @unknown default:
                #if targetEnvironment(simulator)
                return .unavailable(.noEngineOnThisDevice)
                #else
                return .downloadedModel
                #endif
            }

        @unknown default:
            return .unavailable(.noEngineOnThisDevice)
        }
    }

    // MARK: Capability questions the UI asks

    /// Whether Smart Insights can run at all here.
    ///
    /// The paywall is gated on this. Selling a feature the device cannot
    /// perform is both an App Review problem and a refund waiting to happen.
    var canRunSmartInsights: Bool {
        switch backend {
        case .appleIntelligence, .downloadedModel: true
        case .unavailable: false
        }
    }

    /// True only on the MLX path. The setup screen, the progress bar and the
    /// "remove model" row should all hide themselves when this is false.
    var requiresDownload: Bool {
        backend == .downloadedModel
    }

    var unavailableReason: InsightUnavailableReason? {
        if case .unavailable(let reason) = backend { return reason }
        return nil
    }

    /// One line for Settings, so it is always clear what is actually running.
    var backendDescription: String {
        switch backend {
        case .appleIntelligence: "Apple Intelligence · on-device, nothing to download"
        case .downloadedModel: "Downloadable model · on-device"
        case .unavailable(let reason): reason.headline
        }
    }

    // MARK: Session health

    /// Apple's model can report `.available` and then fail every single
    /// generation. The usual cause is a device (or Simulator) where
    /// `SystemLanguageModel` finds an availability record but the on-device
    /// asset catalog is empty — "There are no underlying assets ... for asset
    /// set com.apple.modelcatalog". No availability API predicts this; it is
    /// only observable by trying.
    ///
    /// Without this flag every entry pays the cost of a doomed generation
    /// before falling back, and each attempt logs the same catalog error
    /// several times over. One failed session is enough to stop asking.
    private var appleDisabledForSession = false
    private var appleFailureCount = 0

    /// Two, not one: a single failure can be a guardrail trip or a context
    /// overflow on one unusual entry, which says nothing about the model's
    /// health. Missing assets are fatal immediately — retrying cannot fix a
    /// catalog that is empty.
    private static let appleFailureLimit = 2

    func noteGenerationFailure(_ error: Error) {
        guard backend == .appleIntelligence else { return }
        if let generation = error as? LanguageModelSession.GenerationError,
           case .assetsUnavailable = generation {
            appleDisabledForSession = true
            return
        }
        appleFailureCount += 1
        if appleFailureCount >= Self.appleFailureLimit {
            appleDisabledForSession = true
        }
    }

    func noteGenerationSuccess() {
        appleFailureCount = 0
    }

    /// True when the Apple path was working and has stopped. Callers use this
    /// to explain a degraded result rather than silently returning worse
    /// output.
    var didFallBackFromAppleIntelligence: Bool {
        backend == .appleIntelligence && appleDisabledForSession
    }

    // MARK: Readiness

    func isReady() async -> Bool {
        switch backend {
        case .appleIntelligence:
            // Resident on the system, so nothing to load — but useless if it
            // has already proved it cannot generate.
            return !appleDisabledForSession
        case .downloadedModel:
            return await LocalInsightEngine.shared.isReady()
        case .unavailable:
            return false
        }
    }

    /// Only does anything on the MLX path.
    func prepare(progressHandler: @escaping @Sendable (Float, Double?) -> Void) async throws {
        switch backend {
        case .appleIntelligence:
            return
        case .downloadedModel:
            try await LocalInsightEngine.shared.prepare(progressHandler: progressHandler)
        case .unavailable:
            throw InsightEngineError.noEngineAvailable
        }
    }

    // MARK: Work

    func analyze(_ transcript: String) async throws -> AnalysisResult {
        switch backend {
        case .appleIntelligence:
            do {
                let result = try await FoundationInsightEngine.shared.analyze(transcript)
                noteGenerationSuccess()
                return result
            } catch {
                noteGenerationFailure(error)
                throw error
            }
        case .downloadedModel:
            return try await LocalInsightEngine.shared.analyze(transcript)
        case .unavailable:
            throw InsightEngineError.noEngineAvailable
        }
    }

    func clean(_ transcript: String) async throws -> String {
        switch backend {
        case .appleIntelligence:
            do {
                let cleaned = try await FoundationInsightEngine.shared.clean(transcript)
                noteGenerationSuccess()
                return cleaned
            } catch {
                noteGenerationFailure(error)
                throw error
            }
        case .downloadedModel:
            return try await LocalInsightEngine.shared.clean(transcript)
        case .unavailable:
            // Cleanup is cosmetic; the raw transcript is still the truth.
            return transcript
        }
    }

    /// Cross-entry synthesis — the premium feature.
    ///
    /// Only offered on Apple Intelligence. The 1B MLX model was measured
    /// producing generic, uncited output on this task even with clusters
    /// supplied, and a paid feature that reads like a horoscope is worse for
    /// the product than one that is honestly unavailable. MLX devices keep
    /// per-entry Smart Insights, which is what they can do well.
    func synthesise(entries: [SynthesisEntry], periodLabel: String) async -> JournalSynthesis? {
        guard backend == .appleIntelligence, !appleDisabledForSession else { return nil }
        return await FoundationSynthesizer.shared.synthesise(entries: entries, periodLabel: periodLabel)
    }

    var supportsSynthesis: Bool {
        backend == .appleIntelligence
    }
}
