import Foundation
import SwiftUI

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
    /// 0–1 while the insight model downloads; nil otherwise.
    private(set) var insightDownloadProgress: Float?
    private(set) var insightError: String?

    // Stored (observable) disk status — refreshed after any model change so
    // Settings re-renders without manual tokens.
    private(set) var whisperCached = false
    private(set) var whisperSizeBytes: Int64 = 0
    private(set) var insightCached = false
    private(set) var insightSizeBytes: Int64 = 0

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        whisperCached = SpeechService.isModelCached
        whisperSizeBytes = SpeechService.whisperModelsSizeBytes
        insightCached = Self.isInsightModelCached()
        insightSizeBytes = Self.directorySize(Self.insightDownloadBase)
    }

    // MARK: Status

    static func isInsightModelCached() -> Bool {
        let dirName = insightModelID.replacingOccurrences(of: "/", with: "--")
        let dir = insightDownloadBase.appendingPathComponent("models--\(dirName)")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
    }

    var isInsightDownloading: Bool {
        insightDownloadProgress != nil
    }

    // MARK: Insight model lifecycle

    func downloadInsightModel() async {
        guard insightDownloadProgress == nil else { return }
        insightError = nil
        insightDownloadProgress = 0
        do {
            try await LocalInsightEngine.shared.prepare { [weak self] fraction in
                Task { @MainActor in
                    self?.insightDownloadProgress = fraction
                }
            }
            insightDownloadProgress = nil
            insightReady = true
            refreshStatus()
        } catch {
            insightDownloadProgress = nil
            insightError = error.localizedDescription
        }
    }

    func deleteInsightModel() async {
        await LocalInsightEngine.shared.unload()
        try? FileManager.default.removeItem(at: Self.insightDownloadBase)
        insightReady = false
        insightError = nil
        insightDownloadProgress = nil
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
