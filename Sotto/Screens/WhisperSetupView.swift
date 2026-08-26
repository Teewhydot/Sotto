//  Shown once when the user first taps the mic and the model hasn't been downloaded yet.
//  After completion the parent dismisses this sheet and opens RecordingView.
//

import SwiftUI

struct WhisperSetupView: View {
    @Bindable var speechService: SpeechService
    var onComplete: () -> Void

    @State private var animatePulse = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#1D1E22"), Color(hex: "#2B2A2E"), Color(hex: "#1A1A1D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer()

                // ── Icon ──────────────────────────────────────────────────
                ZStack {
                    Circle()
                        .stroke(Color.sottoAccent.opacity(0.2), lineWidth: 1)
                        .frame(width: 130, height: 130)
                        .scaleEffect(animatePulse ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animatePulse)

                    Circle()
                        .fill(Color.sottoAccent.opacity(0.12))
                        .frame(width: 100, height: 100)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.sottoAccent)
                }
                .padding(.bottom, 32)
                .onAppear { animatePulse = true }

                // ── Heading ───────────────────────────────────────────────
                Text("Set Up Voice Transcription")
                    .font(.title2).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Sotto uses an on-device AI model to transcribe your voice — privately, with no audio ever leaving your device.")
                    .font(.callout).fontDesign(.rounded)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 32)

                // ── Model details ─────────────────────────────────────────
                HStack(spacing: 20) {
                    ModelInfoPill(icon: "internaldrive", label: "~40–80 MB")
                    ModelInfoPill(icon: "lock.shield", label: "On-device")
                    ModelInfoPill(icon: "arrow.down.circle", label: "One-time")
                }
                .padding(.top, 28)

                Spacer()

                // ── Progress area ─────────────────────────────────────────
                VStack(spacing: 16) {
                    switch speechService.whisperState {

                    case .notDownloaded:
                        Button {
                            Task { await speechService.downloadAndLoad() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download Model")
                                    .fontWeight(.semibold).fontDesign(.rounded)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.sottoAccent, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 28)

                    case .downloading(let progress):
                        VStack(spacing: 14) {
                            HStack {
                                Text("Downloading model…")
                                    .font(.subheadline).fontDesign(.rounded)
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int((progress * 100).rounded()))%")
                                    .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.sottoAccent)
                                    .contentTransition(.numericText())
                            }
                            .padding(.horizontal, 28)

                            // Determinate progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // Track
                                    Capsule()
                                        .fill(.white.opacity(0.1))
                                        .frame(height: 6)
                                    // Fill
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.sottoAccent, Color(hex: "#F2CC8F")],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6)
                                        .animation(.easeOut(duration: 0.2), value: progress)
                                }
                            }
                            .frame(height: 6)
                            .padding(.horizontal, 28)

                            Text("One-time download — the model is cached permanently.")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.4))
                        }

                    case .downloaded, .loading:
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                                Text(speechService.whisperState == .loading ? "Initialising model…" : "Preparing…")
                                    .font(.subheadline).fontDesign(.rounded)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Text("Loading into memory — this takes a few seconds.")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.4))
                        }

                    case .ready:
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(hex: "#10B981"))
                                Text("Model ready")
                                    .font(.subheadline).fontDesign(.rounded)
                                    .foregroundStyle(.white.opacity(0.9))
                            }

                            Button {
                                onComplete()
                            } label: {
                                Text("Start Recording")
                                    .fontWeight(.semibold).fontDesign(.rounded)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color(hex: "#10B981"), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .padding(.horizontal, 28)
                        }

                    case .failed(let msg):
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Download failed")
                                    .font(.subheadline).fontDesign(.rounded)
                                    .foregroundStyle(.white.opacity(0.9))
                            }

                            Text(msg)
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)

                            HStack(spacing: 12) {
                                Button {
                                    Task { await speechService.downloadAndLoad() }
                                } label: {
                                    Text("Retry")
                                        .fontWeight(.semibold).fontDesign(.rounded)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.sottoAccent, in: RoundedRectangle(cornerRadius: 14))
                                }

                                Button {
                                    onComplete() // open recording with SFSpeech fallback
                                } label: {
                                    Text("Use Fallback")
                                        .fontWeight(.semibold).fontDesign(.rounded)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Supporting view
struct ModelInfoPill: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.sottoAccent)
            Text(label)
                .font(.caption2).fontDesign(.rounded)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
