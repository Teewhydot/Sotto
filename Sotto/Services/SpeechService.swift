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
    var isModelCached: Bool {
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

    // MARK: - Download + Load
    /// Downloads model (if needed) into Application Support, then loads into memory.
    /// Drives `whisperState` throughout. Safe to call multiple times.
    func downloadAndLoad() async {
        guard whisperKit == nil else {
            whisperState = .ready
            return
        }

        do {
            // Resolve the best model name for this device
            let recommended = WhisperKit.recommendedModels()
            let modelName = recommended.supported.first ?? recommended.disabled.first ?? "tiny.en"
            resolvedModelName = modelName

            let modelDir = Self.modelStorageURL.appendingPathComponent(modelName)
            let alreadyOnDisk = FileManager.default.fileExists(atPath: modelDir.path)

            if alreadyOnDisk {
                // Cached — load straight from disk, no network at all
                whisperState = .loading
                let kit = try await WhisperKit(
                    model: modelName,
                    modelFolder: modelDir.path,
                    verbose: false,
                    logLevel: .none,
                    load: true,
                    download: false
                )
                self.whisperKit = kit
                whisperState = .ready
            } else {
                // First time — download into Application Support
                whisperState = .downloading(0)
                let kit = try await WhisperKit(
                    model: modelName,
                    downloadBase: Self.modelStorageURL,
                    verbose: false,
                    logLevel: .none,
                    prewarm: false,
                    load: true,
                    download: true,
                    useBackgroundDownloadSession: true
                )
                kit.modelStateCallback = { [weak self] (_: ModelState?, newState: ModelState) in
                    Task { @MainActor in
                        switch newState {
                        case .loading: self?.whisperState = .loading
                        case .loaded:  self?.whisperState = .ready
                        default: break
                        }
                    }
                }
                self.whisperKit = kit
                whisperState = .ready
            }

        } catch {
            whisperState = .failed(error.localizedDescription)
        }
    }

    func unloadModel() {
        whisperKit = nil
        whisperState = isModelCached ? .downloaded : .notDownloaded
        clearSamples()
    }

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        let micAuthorized: Bool
        if #available(iOS 17.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

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
            guard let self else { return }
            if let result = result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil {
                self.stopRecording()
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
            transcript = text
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
