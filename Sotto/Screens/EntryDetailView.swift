import SwiftUI

struct EntryDetailView: View {
    let entry: JournalEntry
    @Environment(\.dismiss) var dismiss
    @State private var showFullTranscript = false
    @State private var showObservation = false
    @State private var userNote = ""
    @State private var isFavourite: Bool
    @State private var showRecording = false
    @State private var showShareSheet = false
    @State private var showDeleteAlert = false

    init(entry: JournalEntry) {
        self.entry = entry
        _isFavourite = State(initialValue: entry.isFavourite)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Header ────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.headline).fontDesign(.rounded)

                    HStack(spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute())
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(entry.duration)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(entry.wordCount) words")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // ── Emotion card ──────────────────────────────────────────
                SottoCard {
                    VStack(spacing: 18) {
                        // Emoji bubble
                        ZStack {
                            Circle()
                                .fill(entry.emotionColor.opacity(0.12))
                                .frame(width: 84, height: 84)
                            Text(emotionEmoji(for: entry.primaryEmotion))
                                .font(.system(size: 38))
                        }

                        Text(entry.primaryEmotion)
                            .font(.title3).fontWeight(.semibold).fontDesign(.rounded)
                            .foregroundStyle(entry.emotionColor)

                        VStack(spacing: 12) {
                            MetricBar(
                                label: "Intensity",
                                value: Double(entry.intensity) / 10.0,
                                color: Color(hex: "#EF4444")
                            )
                            MetricBar(
                                label: "Energy",
                                value: Double(entry.energyLevel) / 10.0,
                                color: Color(hex: "#10B981")
                            )
                            ValenceBar(valence: entry.valence)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // ── Themes ────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Themes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entry.themes, id: \.self) { theme in
                                ThemeChip(label: theme)
                            }
                        }
                    }
                }

                // ── Follow-up question ────────────────────────────────────
                SottoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left.fill")
                                .foregroundStyle(Color.sottoAccent)
                                .font(.caption)
                            Text("A question for you")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(Color.sottoAccent)
                        }

                        Text(entry.followUpQuestion)
                            .font(.body).fontDesign(.rounded)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)

                        Button {
                            showRecording = true
                        } label: {
                            Label("Respond to this", systemImage: "arrow.turn.down.right")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(Color.sottoAccent)
                        }
                    }
                }

                // ── Hidden observation ────────────────────────────────────
                SottoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("Something I noticed")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }

                        if showObservation {
                            Text(entry.hiddenObservation)
                                .font(.callout).fontDesign(.rounded)
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .transition(.opacity)
                        } else {
                            Label("Tap to reveal", systemImage: "hand.tap.fill")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeIn(duration: 0.45)) {
                            showObservation = true
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeIn(duration: 0.45)) {
                            showObservation = true
                        }
                    }
                }

                // ── Transcript ────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "What You Said")

                    SottoCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                showFullTranscript
                                    ? entry.transcript
                                    : String(entry.transcript.prefix(150)) + "…"
                            )
                            .font(.body).fontDesign(.serif)
                            .foregroundStyle(.primary)
                            .lineSpacing(5)

                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showFullTranscript.toggle()
                                }
                            } label: {
                                Text(showFullTranscript ? "Show less ↑" : "Show full transcript ↓")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(Color.sottoAccent)
                            }

                            if showFullTranscript {
                                Divider()
                                HStack(spacing: 16) {
                                    Label("\(entry.wordCount) words", systemImage: "text.alignleft")
                                    Label("72% unique — expressive", systemImage: "sparkles")
                                }
                                .font(.caption2).foregroundStyle(.tertiary)
                                .transition(.opacity)
                            }
                        }
                    }
                }

                // ── My note ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "My Note")
                    SottoCard {
                        TextField("Add a private note…", text: $userNote, axis: .vertical)
                            .font(.callout).fontDesign(.rounded)
                            .lineLimit(3...6)
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { isFavourite.toggle() }
                } label: {
                    Image(systemName: isFavourite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavourite ? .red : .primary)
                }

                Menu {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share Transcript", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $showRecording) {
            RecordingView()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [entry.transcript])
        }
        .alert("Delete Entry?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("This entry will be permanently deleted.")
        }
    }
}

/*
#Preview("Entry Detail — Reflective") {
    NavigationStack {
        EntryDetailView(entry: mockEntries[0])
    }
}
#Preview("Entry Detail — Grateful") {
    NavigationStack {
        EntryDetailView(entry: mockEntries[1])
    }
}
#Preview("Entry Detail — dark") {
    NavigationStack {
        EntryDetailView(entry: mockEntries[4])
    }
    .preferredColorScheme(.dark)
}
*/
