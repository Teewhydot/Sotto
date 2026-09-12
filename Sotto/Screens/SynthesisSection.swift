import SwiftUI
import SwiftData

/// The premium half of the Insights screen: patterns read across many entries
/// rather than within one.
///
/// This replaced a hardcoded switch statement and a fixed string. The screen
/// previously showed "Take a moment to reflect on what sits beneath the
/// anxious feelings" to everybody, forever, which is the sort of thing a
/// subscriber notices they are paying for.
///
/// Every claim here carries its evidence, and the evidence is tappable. That
/// is the whole design: the model supplies wording, `SynthesisClustering`
/// supplies the entries, so nothing on screen rests on an entry that does not
/// exist.
struct SynthesisSection: View {
    let entries: [JournalEntry]
    let periodLabel: String

    @State private var premium = PremiumManager.shared
    @State private var engines = InsightEngines.shared
    @State private var store = SynthesisStore.shared

    @State private var showPaywall = false
    @State private var expandedTheme: String?
    @State private var selectedEntry: JournalEntry?

    private var synthesisEntries: [SynthesisEntry] {
        entries.map {
            SynthesisEntry(
                id: $0.id,
                date: $0.date,
                transcript: $0.transcript,
                primaryEmotion: $0.primaryEmotion,
                themes: $0.themes,
                valence: $0.valence,
                intensity: $0.intensity
            )
        }
    }

    private var key: String {
        SynthesisStore.fingerprint(periodLabel: periodLabel, entries: synthesisEntries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Patterns Across Your \(periodLabel)")

            SottoCard {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if !premium.isSmartInsightsUnlocked {
                        locked
                    } else if !engines.supportsSynthesis {
                        unsupported
                    } else if entries.count < SynthesisClustering.minimumSupport {
                        needsMoreEntries
                    } else {
                        content
                    }
                }
            }
        }
        .onAppear { engines.refresh() }
        .task(id: key) {
            guard premium.isSmartInsightsUnlocked, engines.supportsSynthesis else { return }
            guard entries.count >= SynthesisClustering.minimumSupport else { return }
            store.generate(key: key, entries: synthesisEntries, periodLabel: periodLabel)
        }
        .onChange(of: premium.isSmartInsightsUnlocked) { _, unlocked in
            // A lapsed subscriber must not keep reading a cached synthesis.
            if !unlocked { store.clear() }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(onComplete: { showPaywall = false })
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack { EntryDetailView(entry: entry) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.sottoAccent)
            Text("Patterns")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Color.sottoAccent)

            Spacer()

            if case .generating = store.state(for: key), premium.isSmartInsightsUnlocked {
                ProgressView().controlSize(.mini)
            }
        }
    }

    // MARK: States

    private var locked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your entries hold patterns you can't see one at a time — a theme that keeps costing you, a week where something shifted.")
                .font(.callout).fontDesign(.rounded)
                .foregroundStyle(.primary)
                .lineSpacing(4)

            Text("Smart Insights reads across every entry in this period and shows you what recurs, with the entries behind each observation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Button {
                showPaywall = true
            } label: {
                Label("Unlock Smart Insights", systemImage: "lock.open")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.sottoAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var unsupported: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = engines.unavailableReason {
                Text(reason.headline)
                    .font(.callout.weight(.medium)).fontDesign(.rounded)
                Text(reason.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            } else {
                // The MLX path can analyse a single entry well but was
                // measured producing generic, uncited output on cross-entry
                // synthesis, so it is not offered here rather than offered
                // badly.
                Text("Cross-entry patterns need Apple Intelligence")
                    .font(.callout.weight(.medium)).fontDesign(.rounded)
                Text("Your individual entries still get full Smart Insights on this device. Reading across a whole period needs the model built into newer iPhones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    private var needsMoreEntries: some View {
        Text("A few more entries and patterns start to show. Three in a period is the least it takes to tell a pattern from a coincidence.")
            .font(.callout).fontDesign(.rounded)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
    }

    @ViewBuilder
    private var content: some View {
        switch store.state(for: key) {
        case .idle, .generating:
            Text("Reading your \(periodLabel.lowercased())…")
                .font(.callout).fontDesign(.rounded)
                .foregroundStyle(.secondary)

        case .notEnoughYet:
            Text("Nothing recurs often enough in this period to call it a pattern yet. That is an answer too.")
                .font(.callout).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

        case .ready(let synthesis):
            loaded(synthesis)
        }
    }

    @ViewBuilder
    private func loaded(_ synthesis: JournalSynthesis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(synthesis.patterns) { pattern in
                patternRow(pattern, total: synthesis.entryCount)
            }

            if let arc = synthesis.arc {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundStyle(Color(hex: "#8B5CF6"))
                        Text("What shifted")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(Color(hex: "#8B5CF6"))
                    }
                    Text(arc.sentence)
                        .font(.callout).fontDesign(.rounded)
                        .lineSpacing(4)

                    if let id = arc.turningPointEntryID, let entry = entry(for: id) {
                        Button { selectedEntry = entry } label: {
                            Text("It turns here — \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.sottoAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let question = synthesis.question {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color(hex: "#F59E0B"))
                        Text("Worth sitting with")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(Color(hex: "#F59E0B"))
                    }
                    Text(question)
                        .font(.callout).fontDesign(.rounded).italic()
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
            }
        }
    }

    // MARK: Pattern row

    @ViewBuilder
    private func patternRow(_ pattern: SynthesisPattern, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                confidenceBadge(pattern.confidence)
                if pattern.readsWorseThanUsual {
                    Image(systemName: "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(hex: "#EF4444"))
                        .accessibilityLabel("Reads lower than your average")
                }
                Spacer(minLength: 0)
            }

            Text(pattern.sentence)
                .font(.callout).fontDesign(.rounded)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // The evidence count is arithmetic, never model output, so it is
            // safe to state plainly.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedTheme = expandedTheme == pattern.theme ? nil : pattern.theme
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(pattern.support) of your \(total) \(total == 1 ? "entry" : "entries")")
                    Image(systemName: expandedTheme == pattern.theme ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.sottoAccent)
            }
            .buttonStyle(.plain)

            if expandedTheme == pattern.theme {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pattern.evidence) { item in
                        if let entry = entry(for: item.id) {
                            Button { selectedEntry = entry } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(entry.emotionColor)
                                        .frame(width: 6, height: 6)
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Text(entry.primaryEmotion)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if item.id == pattern.clearestEntryID {
                                        Text("clearest")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.sottoAccent)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if pattern.support > pattern.evidence.count {
                        Text("Showing the \(pattern.evidence.count) most recent of \(pattern.support).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, 2)
            }
        }
    }

    private func confidenceBadge(_ confidence: SynthesisPattern.Confidence) -> some View {
        let (label, color): (String, Color) = switch confidence {
        case .strong: ("Strong", Color(hex: "#10B981"))
        case .likely: ("Likely", Color(hex: "#F59E0B"))
        case .tentative: ("Tentative", Color(hex: "#94A3B8"))
        }
        return Text(label.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func entry(for id: UUID) -> JournalEntry? {
        entries.first { $0.id == id }
    }
}
