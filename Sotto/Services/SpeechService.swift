import Foundation
import AVFoundation
import Speech
import WhisperKit
import SwiftUI

// MARK: - Whisper Model State
enum WhisperModelState: Equatable {
    case notDownloaded          // Never downloaded — needs setup flow
    case downloading(Float)     // 0.0–1.0 progress
    case downloaded             // On disk, not in memory
    case loading                // In memory, initialising CoreML
    case ready                  // In memory, ready to transcribe
    case failed(String)
}

    @Observable
final class SpeechService {
    // MARK: - Public State
    var recordingState: ViewState<Bool> = .initial
    var transcript: String = ""
    var isRecording: Bool = false
    var audioPower: Float = 0.0
    var whisperState: WhisperModelState = .notDownloaded

    // MARK: - Live cleanup state
    /// LLM-polished text for the dictation chunks finalized so far.
    private(set) var cleanedTranscript: String = ""
    /// Raw recognizer output that has been harvested for cleaning already.
    private var finalizedRawPrefix = ""
    private var cleanupChain: Task<Void, Never>?

    /// What the user sees while dictating: polished finalized chunks followed
    /// by the raw in-flight partial that hasn't been finalized yet.
    var displayTranscript: String {
        let tail = transcript.hasPrefix(finalizedRawPrefix)
            ? String(transcript.dropFirst(finalizedRawPrefix.count))
            : transcript
        if cleanedTranscript.isEmpty { return tail }
        return tail.isEmpty ? cleanedTranscript : cleanedTranscript + "\n" + tail
    }

    // MARK: - Private
    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Raw mono samples captured during recording — used for the WhisperKit
    // refinement pass after the SFSpeech live transcript.
    private let samplesLock = NSLock()
    private var recordedSamples: [Float] = []
    private var recordSampleRate: Double = 48_000

    // MARK: - Model storage (persistent — survives restarts and low-storage eviction)
    /// Application Support is never evicted by the OS, unlike Library/Caches.
    private static let modelStorageURL: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WhisperModels", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // The model name resolved at runtime from WhisperKit's recommended list
    private var resolvedModelName: String?

    /// True when model files exist in our persistent Application Support directory.
    static var isModelCached: Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: Self.modelStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return false }
        // Any subdirectory = a downloaded model
        return contents.contains { url in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }

    /// Total bytes on disk of all cached Whisper models.
    static var whisperModelsSizeBytes: Int64 {
        directorySize(modelStorageURL)
    }

    /// Deletes every cached Whisper model. They re-download on next use.
    static func deleteCachedWhisperModels() {
        let fm = FileManager.default
        try? fm.removeItem(at: modelStorageURL)
        try? fm.createDirectory(at: modelStorageURL, withIntermediateDirectories: true)
    }

    private static func directorySize(_ url: URL) -> Int64 {
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

    /// Locates an already-downloaded folder for `modelName`, wherever the Hub
    /// layout placed it (handles flat and huggingface-style nesting).
    private func findCachedModelFolder(for modelName: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Self.modelStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if url.lastPathComponent == modelName || url.lastPathComponent.hasSuffix(modelName) {
                return url
            }
        }
        return nil
    }

    // MARK: - Download + Load
    /// Downloads model (if needed) into Application Support, then loads into memory.
    /// Drives `whisperState` throughout. Safe to call multiple times.
    func downloadAndLoad() async {
        guard whisperKit == nil else {
            whisperState = .ready
            return
        }
        // Re-entrancy guard: a double-tap on "Download Model" (or a second
        // caller while one is already in flight) would otherwise start a
        // second concurrent WhisperKit.download() racing the first, with
        // both writing whisperState out of order.
        switch whisperState {
        case .downloading, .loading:
            return
        default:
            break
        }

        do {
            // Resolve the best model name for this device
            let recommended = WhisperKit.recommendedModels()
            let modelName = recommended.supported.first ?? recommended.disabled.first ?? "tiny.en"
            resolvedModelName = modelName

            if let cachedFolder = findCachedModelFolder(for: modelName) {
                // Cached — load straight from disk, no network at all
                whisperState = .loading
                let kit = try await WhisperKit(
                    model: modelName,
                    modelFolder: cachedFolder.path,
                    verbose: false,
                    logLevel: .none,
                    prewarm: false,
                    load: true,
                    download: false
                )
                // WhisperKit's init isn't actor-isolated, so resumption after
                // this await isn't guaranteed to land back on the main
                // thread — hop explicitly before touching observed state.
                await MainActor.run {
                    self.whisperKit = kit
                    self.whisperState = .ready
                }
            } else {
                // First time — download into Application Support with live progress
                whisperState = .downloading(0)
                var lastReportedFraction: Float = -1
                let downloadedFolder = try await WhisperKit.download(
                    variant: modelName,
                    downloadBase: Self.modelStorageURL,
                    useBackgroundSession: true,
                    progressCallback: { [weak self] progress in
                        let fraction = Float(progress.fractionCompleted)
                        // Coalesce rapid callbacks to keep SwiftUI updates cheap
                        guard fraction - lastReportedFraction >= 0.002 || fraction >= 1 else { return }
                        lastReportedFraction = fraction
                        Task { @MainActor in
                            self?.whisperState = .downloading(min(max(fraction, 0), 1))
                        }
                    }
                )

                // Download finished — load into memory
                await MainActor.run { self.whisperState = .loading }
                let kit = try await WhisperKit(
                    model: modelName,
                    modelFolder: downloadedFolder.path,
                    verbose: false,
                    logLevel: .none,
                    prewarm: false,
                    load: true,
                    download: false
                )
                await MainActor.run {
                    self.whisperKit = kit
                    self.whisperState = .ready
                }
            }

        } catch {
            await MainActor.run { self.whisperState = .failed(error.localizedDescription) }
        }
    }

    func unloadModel() {
        whisperKit = nil
        whisperState = Self.isModelCached ? .downloaded : .notDownloaded
        clearSamples()
    }

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        // Deployment target is well above iOS 17, so this is always the path taken.
        let micAuthorized = await AVAudioApplication.requestRecordPermission()

        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        return micAuthorized && speechAuthorized
    }

    // MARK: - Recording
    func startRecording() {
        guard !isRecording else { return }

        transcript = ""
        clearSamples()
        recognitionTask?.cancel()
        recognitionTask = nil
        cleanedTranscript = ""
        finalizedRawPrefix = ""
        cleanupChain?.cancel()
        cleanupChain = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            recordingState = .error(.unknown("Audio session failed: \(error.localizedDescription)"))
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        recordSampleRate = recordingFormat.sampleRate

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            recordingState = .error(.speechRecognitionFailed("Unable to create request"))
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        // SFSpeech provides live partial results during recording;
        // Whisper runs a final high-accuracy pass over the captured audio
        // once recording stops (see refineTranscriptWithWhisper).
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            // Speech delivers this off the main thread — hop before touching
            // any @Observable state so SwiftUI's observers see it safely.
            Task { @MainActor in
                guard let self else { return }
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.harvestFinalChunk()
                    }
                }
                if error != nil {
                    self.stopRecording()
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.appendSamples(from: buffer)
            recognitionRequest.append(buffer)
            self.updatePower(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            recordingState = .loaded(true)
            observeInterruptions()
        } catch {
            recordingState = .error(.unknown("Audio engine failed: \(error.localizedDescription)"))
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        stopObservingInterruptions()
    }

    // MARK: - Interruptions & backgrounding
    // A voice recorder is exactly the app most likely to be interrupted
    // mid-capture (a call, Siri, another app's audio session). Without this,
    // iOS silently deactivates the session and kills the audio engine's tap
    // out from under us: `isRecording` stays true and the UI keeps showing
    // "Recording" while no more audio/transcript is actually being captured.

    private var interruptionObserver: NSObjectProtocol?

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began
            else { return }
            // Stop cleanly rather than let the engine die silently — whatever
            // was captured up to this point is preserved in `transcript`.
            self.stopRecording()
        }
    }

    private func stopObservingInterruptions() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    // MARK: - Live transcript cleanup

    /// Called when the recognizer finalizes an utterance (natural pause).
    /// The newly-finalized chunk is queued for LLM cleanup in order.
    private func harvestFinalChunk() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.transcript.hasPrefix(self.finalizedRawPrefix) else {
                // Recognizer revised earlier text unexpectedly — skip this
                // round; the authoritative cleanup happens when recording ends.
                return
            }
            let delta = String(self.transcript.dropFirst(self.finalizedRawPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.finalizedRawPrefix = self.transcript
            guard !delta.isEmpty else { return }

            let previous = self.cleanupChain
            self.cleanupChain = Task { @MainActor in
                await previous?.value
                let cleaned = await self.cleanDelta(delta)
                guard !cleaned.isEmpty else { return }
                if self.cleanedTranscript.isEmpty {
                    self.cleanedTranscript = cleaned
                } else {
                    self.cleanedTranscript += "\n" + cleaned
                }
            }
        }
    }

    /// Cleans one finalized dictation chunk: local LLM when loaded, quick
    /// heuristics otherwise (and kicks off model download for next time).
    private func cleanDelta(_ delta: String) async -> String {
        if await LocalInsightEngine.shared.isReady() {
            if let cleaned = try? await LocalInsightEngine.shared.clean(delta), !cleaned.isEmpty {
                return cleaned
            }
        } else {
            Task.detached {
                try? await LocalInsightEngine.shared.prepare { _, _ in }
            }
        }
        return NLInsightEngine.lightCleanup(delta)
    }

    /// Authoritative cleanup of the full transcript once recording stops.
    /// Replaces `transcript` with the polished version, guarding against the
    /// LLM silently truncating long entries.
    func cleanTranscriptNow() async {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        var candidate: String?
        if await LocalInsightEngine.shared.isReady() {
            candidate = try? await LocalInsightEngine.shared.clean(raw)
        } else {
            Task.detached {
                try? await LocalInsightEngine.shared.prepare { _, _ in }
            }
        }

        let fallback = NLInsightEngine.lightCleanup(raw)
        let accepted: String
        if let candidate, !candidate.isEmpty,
           Double(candidate.count) >= Double(raw.count) * 0.4,
           Self.isFaithfulCleanup(candidate, to: raw) {
            accepted = candidate
        } else {
            accepted = fallback
        }

        // `clean(_:)` isn't actor-isolated, so its resumption after the
        // `await` above isn't guaranteed to be back on the main thread.
        await MainActor.run {
            self.transcript = accepted
            self.cleanedTranscript = accepted
            self.finalizedRawPrefix = accepted
        }
    }

    /// Catches a small-LLM failure mode the length check alone misses:
    /// instead of truncating, the model pads output by repeating or
    /// hallucinating phrases untethered from what was actually said. Real
    /// cleanup only removes filler/disfluencies, so faithful output should
    /// retain most of the original's distinctive words.
    private static func isFaithfulCleanup(_ candidate: String, to raw: String) -> Bool {
        func significantWords(_ s: String) -> Set<String> {
            Set(
                s.lowercased()
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
                    .filter { $0.count > 2 }
            )
        }
        let rawWords = significantWords(raw)
        guard !rawWords.isEmpty else { return true }
        let overlap = rawWords.intersection(significantWords(candidate)).count
        return Double(overlap) / Double(rawWords.count) >= 0.5
    }

    // MARK: - Whisper refinement pass
    /// Runs the on-device WhisperKit model over the recorded audio and, if it
    /// produces a usable result, replaces the SFSpeech transcript with the more
    /// accurate version. Returns true if the transcript was refined.
    @discardableResult
    func refineTranscriptWithWhisper() async -> Bool {
        guard whisperKit != nil else { return false }
        let samples = snapshotSamples()
        // Skip absurdly short recordings (< 0.4 s of audio).
        guard samples.count > Int(recordSampleRate * 0.4) else { return false }

        let wavURL = Self.writeTemporaryWav(samples: samples, sampleRate: 16_000)
        guard let wavURL else { return false }
        defer { try? FileManager.default.removeItem(at: wavURL) }

        do {
            let results = try await whisperKit!.transcribe(audioPath: wavURL.path)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count >= transcript.trimmingCharacters(in: .whitespaces).count / 2 else {
                return false
            }
            // WhisperKit's transcribe isn't actor-isolated, so resumption
            // after the await above isn't guaranteed to be on the main thread.
            await MainActor.run { self.transcript = text }
            return true
        } catch {
            // Keep the SFSpeech transcript as a graceful fallback.
            return false
        }
    }

    // MARK: - Sample capture

    private func appendSamples(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        let slice = UnsafeBufferPointer(start: channelData, count: frames)
        let copy = Array(slice)
        samplesLock.lock()
        recordedSamples.append(contentsOf: copy)
        samplesLock.unlock()
    }

    private func snapshotSamples() -> [Float] {
        samplesLock.lock()
        defer { samplesLock.unlock() }
        return recordedSamples
    }

    private func clearSamples() {
        samplesLock.lock()
        recordedSamples.removeAll(keepingCapacity: false)
        samplesLock.unlock()
    }

    // MARK: - Audio conversion helpers

    /// Naive linear-interpolation downsample to `targetRate` mono Float32.
    static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard sourceRate > 0, targetRate > 0, !samples.isEmpty else { return [] }
        guard sourceRate != targetRate else { return samples }
        let ratio = sourceRate / targetRate
        let outputCount = Int(Double(samples.count) / ratio)
        guard outputCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let position = Double(i) * ratio
            let index = Int(position)
            let fraction = Float(position - Double(index))
            if index + 1 < samples.count {
                output[i] = samples[index] * (1 - fraction) + samples[index + 1] * fraction
            } else {
                output[i] = samples[index]
            }
        }
        return output
    }

    /// Writes mono samples as a standards-compliant 16-bit PCM WAV file.
    static func writeTemporaryWav(samples: [Float], sampleRate: Double) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sotto-refine-\(UUID().uuidString).wav")

        // Convert Float32 [-1, 1] to little-endian Int16 PCM.
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }

        let header = Self.wavHeader(
            dataByteCount: UInt32(pcm.count),
            sampleRate: UInt32(sampleRate),
            channels: 1,
            bitsPerSample: 16
        )

        let out = NSMutableData()
        out.append(header)
        out.append(pcm)
        do {
            try out.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func wavHeader(dataByteCount: UInt32, sampleRate: UInt32, channels: UInt32, bitsPerSample: UInt32) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        func le32(_ v: UInt32) -> [UInt8] { [.init(v & 0xFF), .init((v >> 8) & 0xFF), .init((v >> 16) & 0xFF), .init((v >> 24) & 0xFF)] }
        func le16(_ v: UInt32) -> [UInt8] { [.init(v & 0xFF), .init((v >> 8) & 0xFF)] }
        var h: [UInt8] = []
        h += Array("RIFF".utf8); h += le32(36 + dataByteCount); h += Array("WAVE".utf8)
        h += Array("fmt ".utf8); h += le32(16)
        h += le16(1) // PCM
        h += le16(channels); h += le32(sampleRate); h += le32(byteRate); h += le16(blockAlign); h += le16(bitsPerSample)
        h += Array("data".utf8); h += le32(dataByteCount)
        return Data(h)
    }

    // MARK: - Helpers
    private func updatePower(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = buffer.frameLength
        var rms: Float = 0.0
        for i in 0..<Int(frames) {
            rms += channelData[i] * channelData[i]
        }
        rms = sqrt(rms / Float(frames))

        DispatchQueue.main.async {
            let minDb: Float = -60.0
            let db = 20 * log10(max(rms, 0.000001))
            self.audioPower = max(0.0, min(1.0, 1.0 - (db / minDb)))
        }
    }
}
