import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var showFullTranscript = false
    @State private var showObservation = false
    @State private var showRecording = false
    @State private var showShareSheet = false
    @State private var showDeleteAlert = false
    @State private var deleteErrorMessage: String?

    /// The entry this one replied to, resolved lazily — `replyToEntryID` is a
    /// bare UUID (not a SwiftData relationship), so the original may have
    /// since been deleted; `nil` here just means "don't show a link."
    private var repliedToEntry: JournalEntry? {
        guard let targetID = entry.replyToEntryID else { return nil }
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.id == targetID }
        )
        return try? modelContext.fetch(descriptor).first
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

                    if let repliedToEntry {
                        NavigationLink(destination: EntryDetailView(entry: repliedToEntry)) {
                            Label("Response to an earlier entry", systemImage: "arrow.turn.down.right")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(Color.sottoAccent)
                        }
                        .padding(.top, 4)
                    } else if entry.replyToEntryID != nil {
                        Label("Response to an earlier entry (no longer available)", systemImage: "arrow.turn.down.right")
                            .font(.caption).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

                // ── Summary card ──────────────────────────────────────────
                if !entry.summary.isEmpty {
                    SottoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "text.alignleft")
                                    .foregroundStyle(Color.sottoAccent)
                                    .font(.caption)
                                Text("Summary")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(Color.sottoAccent)
                            }
                            Text(entry.summary)
                                .font(.callout).fontDesign(.rounded)
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // ── Emotion card ──────────────────────────────────────────
                SottoCard {
                    VStack(spacing: 12) {
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
                if !entry.themes.isEmpty {
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
                                    : entry.transcript.truncated(to: 150)
                            )
                            .font(.body).fontDesign(.serif)
                            .foregroundStyle(.primary)
                            .lineSpacing(5)

                            if entry.transcript.count > 150 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showFullTranscript.toggle()
                                    }
                                } label: {
                                    Text(showFullTranscript ? "Show less ↑" : "Show full transcript ↓")
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(Color.sottoAccent)
                                }
                            }

                            if showFullTranscript {
                                Divider()
                                HStack(spacing: 16) {
                                    Label("\(entry.wordCount) words", systemImage: "text.alignleft")
                                    Label(uniquenessDescription, systemImage: "sparkles")
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
                        TextField("Add a private note…", text: $entry.note, axis: .vertical)
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
                    Haptics.success()
                    withAnimation(.spring(duration: 0.3)) { entry.isFavourite.toggle() }
                } label: {
                    Image(systemName: entry.isFavourite ? "heart.fill" : "heart")
                        .foregroundStyle(entry.isFavourite ? .red : .primary)
                }
                .accessibilityLabel(entry.isFavourite ? "Remove from favourites" : "Add to favourites")

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
                .accessibilityLabel("Entry options")
            }
        }
        .fullScreenCover(isPresented: $showRecording) {
            RecordingView(replyTo: entry.id)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
        .alert("Delete Entry?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
        } message: {
            Text("This entry will be permanently deleted.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func deleteEntry() {
        Haptics.warning()
        modelContext.delete(entry)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            deleteErrorMessage = "The entry couldn't be deleted: \(error.localizedDescription)"
        }
    }

    // MARK: - Derived values

    private var shareText: String {
        """
        \(entry.date.formatted(date: .long, time: .omitted))

        \(entry.transcript)
        """
    }

    /// Real lexical diversity of the transcript, replacing the old hardcoded stat.
    private var uniquenessDescription: String {
        let diversity = Stats.lexicalDiversity(entry.transcript)
        let percent = Int((diversity * 100).rounded())
        let descriptor: String
        switch diversity {
        case 0.65...: descriptor = "richly varied"
        case 0.45..<0.65: descriptor = "balanced"
        default: descriptor = "focused"
        }
        return "\(percent)% unique words — \(descriptor)"
    }
}

#Preview("Entry Detail — Relieved") {
    NavigationStack {
        EntryDetailView(entry: MockData.sampleEntries[0])
    }
    .modelContainer(MockData.previewContainer)
}
#Preview("Entry Detail — Exhausted") {
    NavigationStack {
        EntryDetailView(entry: MockData.sampleEntries[1])
    }
    .modelContainer(MockData.previewContainer)
}
#Preview("Entry Detail — dark") {
    NavigationStack {
        EntryDetailView(entry: MockData.sampleEntries[2])
    }
    .modelContainer(MockData.previewContainer)
    .preferredColorScheme(.dark)
}
