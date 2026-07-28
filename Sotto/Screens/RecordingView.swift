import SwiftUI
import Combine

// MARK: - Animated Waveform
struct WaveformView: View {
    let isActive: Bool
    let power: Float
    
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.1, count: 42)
    let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

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
    
    @State private var speechService = SpeechService()
    @State private var showSetup = false
    
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
                ScrollView {
                    Text("\(Text(speechService.transcript).foregroundColor(.white))\(Text(showTranscriptCursor ? "▌" : " ").foregroundColor(Color.sottoAccent))")
                    .font(.body).fontDesign(.serif)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                }
                .frame(height: 160)

                Spacer().frame(height: 24)

                // ── Timer + word count ────────────────────────────────────
                HStack(spacing: 8) {
                    Text(formatDuration(elapsedSeconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("·").foregroundStyle(.white.opacity(0.25))
                    Text("\(speechService.transcript.split(separator: " ").count) words")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer().frame(height: 44)

                // ── Controls ──────────────────────────────────────────────
                HStack(spacing: 52) {
                    // Done
                    Button {
                        speechService.stopRecording()
                        showAnalysis = true
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
                speechService.startRecording()
            }
        }
        .task {
            let auth = await speechService.requestPermissions()
            guard auth else {
                speechService.recordingState = .error(.micPermissionDenied)
                return
            }
            if speechService.isModelCached {
                // Already downloaded — load silently and start
                await speechService.downloadAndLoad()
                if speechService.whisperState == .ready {
                    speechService.startRecording()
                } else {
                    // Load failed, still start with SFSpeech fallback
                    speechService.startRecording()
                }
            } else {
                // First time — show the setup flow
                showSetup = true
            }
        }
        .onDisappear {
            speechService.stopRecording()
            speechService.unloadModel()
        }
    }

    func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
