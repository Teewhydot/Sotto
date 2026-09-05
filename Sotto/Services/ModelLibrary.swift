import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Model library
/// Central status + lifecycle for Sotto's on-device AI models (Whisper
/// transcription, MLX insight LLM). Observable so Settings and the setup
/// screens can react to downloads and deletions.
@MainActor
@Observable
final class ModelLibrary {
    static let shared = ModelLibrary()

    /// Base directory for the insight model's huggingface-style snapshot.
    static let insightDownloadBase: URL = FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask
    ).first!.appendingPathComponent("mlx-models", isDirectory: true)

    static let insightModelID = LocalInsightEngine.modelID

    /// True right after a download finishes in-process. Disk presence is the
    /// source of truth across launches (see `isInsightModelCached`).
    private(set) var insightReady = false
    /// 0–1 while the insight model downloads; nil otherwise. Weighted by file
    /// count in the model snapshot, not bytes, so it can sit near-flat for
    /// long stretches while the one large weights file streams in — see
    /// `insightDownloadSpeed` for a signal that isn't skewed by that.
    private(set) var insightDownloadProgress: Float?
    /// Current download throughput in bytes/sec, when the underlying
    /// transfer reports one; nil otherwise (including when not downloading).
    private(set) var insightDownloadSpeed: Double?
    private(set) var insightError: String?

    // Stored (observable) disk status — refreshed after any model change so
    // Settings re-renders without manual tokens.
    private(set) var whisperCached = false
    private(set) var whisperSizeBytes: Int64 = 0
    private(set) var insightCached = false
    private(set) var insightSizeBytes: Int64 = 0

    private init() {
        refreshStatus()
        // The insight model's ~700MB MLX container otherwise stays resident
        // for the whole process lifetime (nothing else ever unloads it — see
        // `unload()`), raising jetsam risk under memory pressure. It reloads
        // transparently next use (SpeechService/AIAnalysisService already
        // re-`prepare()` whenever `isReady()` is false).
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await LocalInsightEngine.shared.unload() }
        }
    }

    func refreshStatus() {
        whisperCached = SpeechService.isModelCached
        whisperSizeBytes = SpeechService.whisperModelsSizeBytes
        insightCached = Self.isInsightModelCached()
        insightSizeBytes = Self.directorySize(Self.insightDownloadBase)
    }

    // MARK: Status

    static func isInsightModelCached() -> Bool {
        // Mirrors HubApi.localRepoLocation: downloadBase/<repoType>/<repoID>,
        // e.g. ".../mlx-models/models/mlx-community/Llama-3.2-1B-Instruct-4bit"
        // — swift-transformers' Hub layout, not the Python huggingface_hub
        // "models--org--repo" cache convention.
        let dir = insightDownloadBase.appendingPathComponent("models").appendingPathComponent(insightModelID)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // Guard against a directory left behind by an interrupted download.
        let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        return !(contents?.isEmpty ?? true)
    }

    var isInsightDownloading: Bool {
        insightDownloadProgress != nil
    }

    /// UI-facing convenience only — decides what Settings/the setup screen
    /// *show* (download button vs. an upgrade prompt). Not the enforcement
    /// point: `LocalInsightEngine.prepare()` gates for real, since callers
    /// like SpeechService's background warm-up never go through here.
    var isInsightEntitled: Bool {
        PremiumManager.shared.isSmartInsightsUnlocked
    }

    // MARK: Insight model lifecycle

    func downloadInsightModel() async {
        guard insightDownloadProgress == nil else { return }
        insightError = nil
        insightDownloadProgress = 0
        insightDownloadSpeed = nil
        do {
            try await LocalInsightEngine.shared.prepare { [weak self] fraction, speed in
                Task { @MainActor in
                    self?.insightDownloadProgress = fraction
                    self?.insightDownloadSpeed = speed
                }
            }
            insightDownloadProgress = nil
            insightDownloadSpeed = nil
            insightReady = true
            refreshStatus()
        } catch {
            insightDownloadProgress = nil
            insightDownloadSpeed = nil
            insightError = error.localizedDescription
        }
    }

    func deleteInsightModel() async {
        await LocalInsightEngine.shared.unload()
        // unload() only stops *new* analyze()/clean() calls from starting —
        // one already mid-generation (e.g. cleaning up the entry you just
        // finished recording) keeps reading weights/tokenizer files straight
        // off disk. Deleting them out from under it crashed the app.
        await LocalInsightEngine.shared.waitForIdle()
        try? FileManager.default.removeItem(at: Self.insightDownloadBase)
        insightReady = false
        insightError = nil
        insightDownloadProgress = nil
        insightDownloadSpeed = nil
        refreshStatus()
    }

    func deleteWhisperModels() {
        SpeechService.deleteCachedWhisperModels()
        refreshStatus()
    }

    // MARK: Sizes

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

