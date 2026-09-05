//  Shown before the first recording session: downloads the local insight LLM
//  that powers live transcript cleanup and journal reflections. Mirrors the
//  WhisperSetupView flow and visual language.
//

import SwiftUI

struct InsightModelSetupView: View {
    var onComplete: () -> Void

    @State private var animatePulse = false
    @State private var showPaywall = false

    private var library: ModelLibrary { ModelLibrary.shared }

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

                    Image(systemName: "sparkles")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.sottoAccent)
                }
                .padding(.bottom, 32)
                .onAppear { animatePulse = true }

                // ── Heading ───────────────────────────────────────────────
                Text("Set Up Smart Insights")
                    .font(.title2).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("A small on-device AI polishes your dictation as you speak and writes your journal reflections — privately, with nothing ever leaving your device.")
                    .font(.callout).fontDesign(.rounded)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 32)

                // ── Model details ─────────────────────────────────────────
                HStack(spacing: 20) {
                    ModelInfoPill(icon: "internaldrive", label: "~700 MB")
                    ModelInfoPill(icon: "lock.shield", label: "On-device")
                    ModelInfoPill(icon: "arrow.down.circle", label: "One-time")
                }
                .padding(.top, 28)

                Spacer()

                // ── Progress area ─────────────────────────────────────────
                VStack(spacing: 16) {
                    if let error = library.insightError {
                        failedView(error)
                    } else if let progress = library.insightDownloadProgress {
                        downloadingView(progress, speed: library.insightDownloadSpeed)
                    } else if library.insightReady {
                        readyView
                    } else if !library.isInsightEntitled {
                        unlockPromptView
                    } else {
                        downloadButton
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(onComplete: { showPaywall = false })
        }
    }

    // MARK: States

    private var unlockPromptView: some View {
        VStack(spacing: 12) {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("Unlock Smart Insights")
                        .fontWeight(.semibold).fontDesign(.rounded)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.sottoAccent, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)

            Button {
                onComplete() // continue without insights — heuristics cover it
            } label: {
                Text("Continue Without Insights")
                    .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var downloadButton: some View {
        Button {
            Task { await library.downloadInsightModel() }
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
    }

    private func downloadingView(_ progress: Float, speed: Double?) -> some View {
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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(height: 6)
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

            // The percentage above is weighted by file count, not bytes, so
            // it can sit still for a long stretch while the one large
            // weights file streams in. Throughput isn't subject to that
            // skew, so it's the more honest "is this actually moving?" signal
            // — shown whenever the transfer reports one.
            Text(captionText(speed))
                .font(.caption).fontDesign(.rounded)
                .foregroundStyle(.white.opacity(0.4))
                .contentTransition(.numericText())
                .animation(.default, value: speed)
        }
    }

    private func captionText(_ speed: Double?) -> String {
        guard let speed, speed > 0 else {
            return "One-time download — the model is cached until you remove it."
        }
        let rate = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
        return "\(rate)/s — cached until you remove it."
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Download failed")
                    .font(.subheadline).fontDesign(.rounded)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(message)
                .font(.caption).fontDesign(.rounded)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 12) {
                Button {
                    Task { await library.downloadInsightModel() }
                } label: {
                    Text("Retry")
                        .fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sottoAccent, in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    onComplete() // continue without insights — heuristics cover it
                } label: {
                    Text("Skip for Now")
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

    private var readyView: some View {
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
                Text("Continue")
                    .fontWeight(.semibold).fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "#10B981"), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)
        }
    }
}
