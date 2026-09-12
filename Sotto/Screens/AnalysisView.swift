import SwiftUI
import SwiftData

struct AnalysisView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    let transcript: String
    let duration: Int
    let wordCount: Int

    /// Set when this entry is a response to a question on another entry.
    var replyTo: UUID? = nil

    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.35
    @State private var rippleScale: CGFloat = 0.6
    @State private var rippleOpacity: Double = 0.0
    
    @State private var analysisService = AIAnalysisService()
    
    // We need to dismiss the whole flow, not just AnalysisView, if it was presented from Recording/TextEntry.
    // However, RecordingView uses .fullScreenCover for AnalysisView. 
    // Dismissing AnalysisView will just return to RecordingView unless we pass a binding or use presentationMode.
    // Since RecordingView is itself presented (from SottoMainView), if we dismiss RecordingView, AnalysisView drops too.
    @Environment(\.presentationMode) var presentationMode
    
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                if case .error(let err) = analysisService.state {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text("Analysis failed")
                            .font(.headline)
                        Text(err.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        VStack(spacing: 10) {
                            Button {
                                Task { await analysisService.analyzeTranscript(transcript) }
                            } label: {
                                Label("Try Again", systemImage: "arrow.clockwise")
                                    .font(.body.weight(.semibold)).fontDesign(.rounded)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.sottoAccent, in: RoundedRectangle(cornerRadius: 14))
                            }

                            Button("Save Without Analysis") {
                                saveEntry(nil)
                            }
                            .font(.subheadline).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                    }
                } else {
                    // Pulsing ring + dot
                    ZStack {
                        // Outer ripple ring
                        Circle()
                            .stroke(Color.sottoAccent.opacity(rippleOpacity), lineWidth: 1.5)
                            .frame(width: 72, height: 72)
                            .scaleEffect(rippleScale)
                            .onAppear {
                                rippleOpacity = 1.0
                                withAnimation(
                                    .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                                ) {
                                    rippleScale = 1.8
                                    rippleOpacity = 0
                                }
                            }

                        // Inner dot
                        Circle()
                            .fill(Color.sottoAccent)
                            .frame(width: 22, height: 22)
                            .scaleEffect(scale)
                            .opacity(opacity)
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                                ) {
                                    scale = 1.25
                                    opacity = 1.0
                                }
                            }
                    }

                    VStack(spacing: 10) {
                        Text("Sotto is with you.")
                            .font(.title3).fontWeight(.medium).fontDesign(.rounded)
                            .foregroundStyle(.primary)

                        Text("Reflecting on what you shared…")
                            .font(.subheadline).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Stats
                HStack(spacing: 14) {
                    Text("\(wordCount) words")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if duration > 0 {
                        Text("·").foregroundStyle(Color(.quaternaryLabel))
                        Text(formatDuration(duration))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let progress = analysisService.modelDownloadProgress {
                    Text("Upgrading on-device insights… \(Int((progress * 100).rounded()))%")
                        .font(.caption2).fontDesign(.rounded)
                        .foregroundStyle(.tertiary)
                }

                Spacer().frame(height: 44)
            }
        }
        .task {
            // Start analysis
            await analysisService.analyzeTranscript(transcript)
        }
        .onChange(of: analysisService.state) { oldState, newState in
            if case .loaded(let result) = newState {
                saveEntry(result)
            }
        }
        .feedbackOverlay()
    }
    
    private func saveEntry(_ result: AnalysisResult?) {
        let newEntry = JournalEntry(
            date: Date(),
            transcript: transcript,
            summary: result?.summary ?? "No summary available.",
            duration: duration > 0 ? formatDuration(duration) : "—",
            wordCount: wordCount,
            primaryEmotion: result?.primaryEmotion ?? "Neutral",
            intensity: result?.intensity ?? 5,
            energyLevel: result?.energyLevel ?? 5,
            valence: result?.valence ?? 0.0,
            themes: result?.themes ?? [],
            // No canned stand-in: an entry with no real question stores "",
            // and both screens that render it hide the section.
            followUpQuestion: result?.followUpQuestion ?? "",
            hiddenObservation: result?.hiddenObservation ?? "",
            replyToEntryID: replyTo
        )

        modelContext.insert(newEntry)

        // This is the only save for every entry in the app. It used to be
        // `try?` followed unconditionally by a success haptic and a dismiss,
        // so a failed save buzzed "saved" and closed the screen over an entry
        // that no longer existed anywhere.
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(newEntry)
            FeedbackCenter.shared.error(
                "Couldn't save this entry",
                error,
                retryLabel: "Try Again",
                retry: { saveEntry(result) }
            )
            return
        }

        FeedbackCenter.shared.success("Entry saved")
        onComplete()
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%dm %02ds", m, s)
    }
}
