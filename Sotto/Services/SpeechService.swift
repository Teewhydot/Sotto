//
//  SpeechService.swift
//  Sotto
//

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
            let recommended = await WhisperKit.recommendedModels()
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

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            recordingState = .error(.speechRecognitionFailed("Unable to create request"))
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        // Always use SFSpeech for live partial results during recording
        // Whisper will run a final high-accuracy pass when recording stops
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
            self?.recognitionRequest?.append(buffer)
            self?.updatePower(buffer: buffer)
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
