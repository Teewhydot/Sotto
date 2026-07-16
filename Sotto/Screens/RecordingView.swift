//
//  RecordingView.swift
//  Sotto
//

import SwiftUI
import Combine

// MARK: - Animated Waveform
struct MockWaveformView: View {
    let isActive: Bool
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
                amplitudes = Array(amplitudes.dropFirst()) + [CGFloat.random(in: 0.05...0.95)]
            }
        }
    }
}

// MARK: - Recording View
struct RecordingView: View {
    @Environment(\.dismiss) var dismiss

    @State private var isRecording = true
    @State private var isPaused = false
    @State private var elapsedSeconds = 107
    @State private var wordCount = 214
    @State private var showTranscriptCursor = true
    @State private var showAnalysis = false

    let committedText = "I've been thinking about the conversation we had yesterday and whether I handled it the right way. I keep coming back to the moment when I said something that I didn't mean to say in that way. I think I was trying to be direct but it came out differently."
    @State private var partialText = "It's been sitting with me all da"

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let cursorTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.sottoRecordingBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top bar ───────────────────────────────────────────────
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.body).fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                // ── Recording indicator badge ─────────────────────────────
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPaused ? Color(hex: "#F59E0B") : Color(hex: "#EF4444"))
                        .frame(width: 8, height: 8)
                        .opacity(isPaused ? 1 : (showTranscriptCursor ? 1 : 0.3))
                    Text(isPaused ? "Paused" : "Recording")
                        .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.08), in: Capsule())

                Spacer().frame(height: 28)

                // ── Waveform ──────────────────────────────────────────────
                MockWaveformView(isActive: isRecording && !isPaused)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                // ── Live transcript ───────────────────────────────────────
                ScrollView {
                    Text("\(Text(committedText + " ").foregroundColor(.white))\(Text(partialText).foregroundColor(.white.opacity(0.45)))\(Text(showTranscriptCursor ? "▌" : " ").foregroundColor(Color.sottoAccent))")
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
                    Text("\(wordCount) words")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer().frame(height: 44)

                // ── Controls ──────────────────────────────────────────────
                HStack(spacing: 52) {
                    // Pause / Resume
                    Button {
                        withAnimation(.spring(duration: 0.3)) { isPaused.toggle() }
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.white.opacity(0.1), in: Circle())
                    }

                    // Done
                    Button {
                        showAnalysis = true
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(.white).frame(width: 62, height: 62)
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.sottoRecordingBG)
                            }
                            Text("Done")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }

                Spacer().frame(height: 56)
            }
        }
        .fullScreenCover(isPresented: $showAnalysis) {
            AnalysisView()
        }
        .onReceive(timer) { _ in
            guard isRecording && !isPaused else { return }
            elapsedSeconds += 1
            if elapsedSeconds % 3 == 0 { wordCount += Int.random(in: 2...5) }
        }
        .onReceive(cursorTimer) { _ in
            showTranscriptCursor.toggle()
        }
    }

    func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview("Recording — active") {
    RecordingView()
}
