import SwiftUI
import Combine

// MARK: - Animated Waveform
struct WaveformView: View {
    let isActive: Bool
    let power: Float
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.1, count: 42)
    // @State, not a plain `let` — WaveformView is reconstructed on every
    // RecordingView.body re-evaluation (which fires on nearly every audio
    // buffer via `speechService.audioPower`); a plain stored property would
    // re-run `Timer.publish(...).autoconnect()` on each of those, stacking
    // up concurrent live timers instead of reusing one.
    @State private var timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2.5
            let midY = size.height / 2
            let totalWidth = CGFloat(amplitudes.count) * (barWidth + spacing)
            let startX = (size.width - totalWidth) / 2

            for (i, amplitude) in amplitudes.enumerated() {
                let x = startX + CGFloat(i) * (barWidth + spacing)
                let barHeight = max(amplitude, 0.04) * size.height * 0.85
                let rect = CGRect(
                    x: x, y: midY - barHeight / 2,
                    width: barWidth, height: barHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: 1.5)
                let opacity = isActive ? (0.35 + Double(amplitude) * 0.65) : 0.18
                context.fill(path, with: .color(Color.sottoAccent.opacity(opacity)))
            }
        }
        .frame(height: 100)
        .onReceive(timer) { _ in
            guard isActive else { return }
            withAnimation(.linear(duration: 0.08)) {
                // Mix random jitter with actual mic power for organic feel
                let randomJitter = CGFloat.random(in: -0.1...0.3)
                let mixedPower = max(0.1, CGFloat(power) + randomJitter)
                amplitudes = Array(amplitudes.dropFirst()) + [min(mixedPower, 0.95)]
            }
        }
    }
}

// MARK: - Recording View
struct RecordingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Set when recording in response to a question on another entry.
    var replyTo: UUID? = nil

    @State private var speechService = SpeechService()
    @State private var showSetup = false
    @State private var showInsightSetup = false
    @State private var isRefining = false
    @State private var isCleaning = false

    @State private var elapsedSeconds = 0
    @State private var showTranscriptCursor = true
    @State private var showAnalysis = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let cursorTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.sottoRecordingBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top bar ───────────────────────────────────────────────
                HStack {
                    Spacer()
                    Button {
                        speechService.stopRecording()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.body).fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                // ── Status ────────────────────────────────────────────────
                if case .error(let err) = speechService.recordingState {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title).foregroundStyle(.red)
                        Text(err.localizedDescription)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else if isRefining || isCleaning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                        Text(isCleaning ? "Polishing transcription…" : "Refining transcription…")
                            .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.08), in: Capsule())
                } else {
                    // Recording Indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#EF4444"))
                            .frame(width: 8, height: 8)
                            .opacity(showTranscriptCursor ? 1 : 0.3)
                        Text(speechService.isRecording ? "Recording" : "Ready")
                            .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.08), in: Capsule())
                }

                Spacer().frame(height: 28)

                // ── Waveform ──────────────────────────────────────────────
                WaveformView(isActive: speechService.isRecording, power: speechService.audioPower)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                // ── Live transcript ───────────────────────────────────────
                ScrollViewReader { proxy in
                    ScrollView {
                        Text("\(Text(speechService.displayTranscript).foregroundColor(.white))\(Text(showTranscriptCursor ? "▌" : " ").foregroundColor(Color.sottoAccent))")
                        .font(.body).fontDesign(.serif)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)

                        // Invisible anchor pinned to the end of the transcript
                        Color.clear
                            .frame(height: 1)
                            .id("transcriptBottom")
                    }
                    .frame(height: 160)
                    .onChange(of: speechService.displayTranscript) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("transcriptBottom", anchor: .bottom)
                        }
                    }
                }

                Spacer().frame(height: 24)

                // ── Timer + word count ────────────────────────────────────
                HStack(spacing: 8) {
                    Text(formatDuration(elapsedSeconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("·").foregroundStyle(.white.opacity(0.25))
                    Text("\(speechService.displayTranscript.split(separator: " ").count) words")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer().frame(height: 44)

                // ── Controls ──────────────────────────────────────────────
                HStack(spacing: 52) {
                    // Done
                    Button {
                        Haptics.impact()
                        finishRecording()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(speechService.isRecording ? .white : .white.opacity(0.3)).frame(width: 62, height: 62)
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.sottoRecordingBG)
                            }
                            Text("Done")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .disabled(!speechService.isRecording)
                }

                Spacer().frame(height: 56)
            }
        }
        .fullScreenCover(isPresented: $showAnalysis) {
            AnalysisView(
                transcript: speechService.transcript,
                duration: elapsedSeconds,
                wordCount: speechService.transcript.split(separator: " ").count,
                replyTo: replyTo,
                onComplete: {
                    showAnalysis = false
                    dismiss()
                }
            )
        }
        .onReceive(timer) { _ in
            guard speechService.isRecording else { return }
            elapsedSeconds += 1
        }
        .onReceive(cursorTimer) { _ in
            showTranscriptCursor.toggle()
        }
        .fullScreenCover(isPresented: $showSetup) {
            WhisperSetupView(speechService: speechService) {
                showSetup = false
                Haptics.tap()
                beginSessionAfterWhisperSetup()
            }
        }
        .fullScreenCover(isPresented: $showInsightSetup) {
            InsightModelSetupView {
                showInsightSetup = false
                startRecordingSession()
            }
        }
        .task {
            let auth = await speechService.requestPermissions()
            guard auth else {
                speechService.recordingState = .error(.micPermissionDenied)
                return
            }
            if SpeechService.isModelCached {
                // Already downloaded — load silently, then check the insight
                // model before starting.
                await speechService.downloadAndLoad()
                beginSessionAfterWhisperSetup()
            } else {
                // First time — show the setup flow
                showSetup = true
            }
        }
        .onDisappear {
            speechService.stopRecording()
            speechService.unloadModel()
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding mid-recording (a call, switching apps, locking
            // the phone) would otherwise leave the audio session force-
            // deactivated out from under a still-"isRecording" UI with no
            // more audio actually being captured. Stop cleanly instead —
            // whatever was captured is preserved in the transcript, and the
            // user can tap Done themselves on return.
            if phase != .active, speechService.isRecording {
                speechService.stopRecording()
            }
        }
    }

    /// After Whisper is available, gate on the insight LLM setup (once ever),
    /// then start recording.
    private func beginSessionAfterWhisperSetup() {
        if !ModelLibrary.isInsightModelCached() && !ModelLibrary.shared.insightReady {
            // Slight delay so back-to-back fullScreenCovers don't swallow
            // the second presentation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showInsightSetup = true
            }
        } else {
            startRecordingSession()
        }
    }

    private func startRecordingSession() {
        Haptics.impact()
        speechService.startRecording()
    }

    /// Stops capture, runs the Whisper refinement pass if available, cleans
    /// the transcript with the local LLM, then hands off to analysis.
    private func finishRecording() {
        speechService.stopRecording()
        Task { @MainActor in
            if speechService.whisperState == .ready {
                isRefining = true
                await speechService.refineTranscriptWithWhisper()
                isRefining = false
            }
            isCleaning = true
            await speechService.cleanTranscriptNow()
            isCleaning = false
            showAnalysis = true
        }
    }

    func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
