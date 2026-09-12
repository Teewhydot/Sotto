import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    @State private var selectedPeriod = "Month"
    let periods = ["Week", "Month", "3 Months"]
    
    var filteredEntries: [JournalEntry] {
        let calendar = Calendar.current
        let now = Date()
        let cutoff: Date
        switch selectedPeriod {
        case "Week":
            cutoff = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case "3 Months":
            cutoff = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        default: // "Month"
            cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        }
        return entries.filter { $0.date >= cutoff }
    }

    var currentStreak: Int {
        Stats.currentStreak(days: Set(entries.map { Calendar.current.startOfDay(for: $0.date) }))
    }
    var totalEntries: Int { entries.count }
    var avgWordsPerEntry: Int {
        guard !entries.isEmpty else { return 0 }
        let totalWords = entries.reduce(0) { $0 + $1.wordCount }
        return totalWords / entries.count
    }

    // Real pattern computation over the selected period
    var dominantEmotion: String? {
        Stats.dominant(filteredEntries.map(\.primaryEmotion))
    }
    var dominantEmotionShare: Double {
        guard let emotion = dominantEmotion else { return 0 }
        return Stats.share(of: emotion, in: filteredEntries.map(\.primaryEmotion))
    }
    var topThemesThisPeriod: [String] {
        Stats.topThemes(filteredEntries.map(\.themes), limit: 3)
    }
    var valenceDirection: String? {
        let values = filteredEntries.map(\.valence)
        guard values.count >= 3 else { return nil }
        let mid = values.count / 2
        let older = values.prefix(mid).reduce(0,+) / Double(mid)
        let recent = values.suffix(from: mid).reduce(0,+) / Double(values.count - mid)
        if recent - older > 0.1 { return "brightening" }
        if older - recent > 0.1 { return "cooling" }
        return "steady"
    }

    private func patternText(for emotion: String) -> String {
        let percent = Int((dominantEmotionShare * 100).rounded())
        let themes = topThemesThisPeriod
        var text = "\(percent)% of your \(filteredEntries.count) entries this period read as \(emotion.lowercased())"
        if let direction = valenceDirection, !themes.isEmpty {
            text += ", with your overall tone \(direction). Recurring themes: "
            text += themes.map(\.localizedLowercase).joined(separator: ", ")
            text += "."
        }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Period picker ─────────────────────────────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(periods, id: \.self) { period in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        selectedPeriod = period
                                    }
                                } label: {
                                    Text(period)
                                        .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .background(
                                            selectedPeriod == period
                                                ? Color.sottoAccent
                                                : Color.sottoSecondary,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(
                                            selectedPeriod == period ? .white : .secondary
                                        )
                                }
                            }
                        }
                    }

                    // ── Summary stats row ─────────────────────────────────
                    HStack(spacing: 12) {
                        InsightStatCard(
                            value: "\(currentStreak)",
                            label: "Day streak",
                            icon: "flame.fill",
                            color: Color(hex: "#F97316")
                        )
                        InsightStatCard(
                            value: "\(totalEntries)",
                            label: "Total entries",
                            icon: "text.bubble.fill",
                            color: Color.sottoAccent
                        )
                        InsightStatCard(
                            value: "\(avgWordsPerEntry)",
                            label: "Avg. words",
                            icon: "character.cursor.ibeam",
                            color: Color(hex: "#10B981")
                        )
                    }

                    // ── Mood calendar ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Mood Calendar")
                        SottoCard {
                            MoodCalendarView(entries: entries)
                        }
                    }

                    // ── Valence trend ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Emotional Tone")
                        SottoCard {
                            ValenceTrendChart(entries: filteredEntries)
                        }
                    }

                    // ── Emotion breakdown ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Emotions This Period")
                        SottoCard {
                            EmotionBreakdownView(entries: filteredEntries)
                        }
                    }

                    // ── Top themes ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Recurring Themes")
                        SottoCard {
                            ThemeCloudView(entries: filteredEntries)
                        }
                    }

                    // ── Pattern summary ───────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "This \(selectedPeriod == "Week" ? "Week" : selectedPeriod == "Month" ? "Month" : "Quarter")")
                        SottoCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.sottoAccent)
                                    Text("Pattern")
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(Color.sottoAccent)
                                }

                                if filteredEntries.isEmpty {
                                    Text("No entries in this period yet.")
                                        .font(.callout).fontDesign(.rounded)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(4)
                                } else if let emotion = dominantEmotion {
                                    // Free tier: arithmetic over the period.
                                    // True, useful, and never more than a
                                    // count — the interpretation lives in
                                    // SynthesisSection below.
                                    Text(patternText(for: emotion))
                                        .font(.callout).fontDesign(.rounded)
                                        .foregroundStyle(.primary)
                                        .lineSpacing(4)
                                }
                            }
                        }
                    }

                    // Premium: patterns read across entries, each with the
                    // entries behind it. Replaced a hardcoded "Invitation"
                    // string that told every user, every period, to "reflect
                    // on what sits beneath" their dominant emotion.
                    SynthesisSection(
                        entries: filteredEntries,
                        periodLabel: selectedPeriod == "Week" ? "Week"
                            : selectedPeriod == "Month" ? "Month" : "Quarter"
                    )

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("Insights")
        }
    }
}

// MARK: - Insight stat card
struct InsightStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
            Text(value)
                .font(.title2).fontWeight(.bold).fontDesign(.rounded)
            Text(label)
                .font(.caption2).fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sottoSecondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Mood Calendar (30-day grid)
struct MoodCalendarView: View {
    var entries: [JournalEntry]

    private var calendarDays: [(date: Date, valence: Double?)] {
        (0..<30).compactMap { daysAgo -> (Date, Double?)? in
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else { return nil }
            let entry = entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
            return (date, entry?.valence)
        }.reversed()
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Day labels
            HStack(spacing: 0) {
                // Indexed, not `id: \.self`: Sunday and Saturday both label
                // "S", Tuesday and Thursday both "T". Identical ids in one
                // ForEach give SwiftUI undefined layout — two of the seven
                // columns were interchangeable as far as it was concerned.
                ForEach(Array(["S","M","T","W","T","F","S"].enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    DayCell(date: day.date, valence: day.valence)
                }
            }

            // Legend
            HStack(spacing: 16) {
                LegendItem(color: Color(hex: "#10B981"), label: "Positive")
                LegendItem(color: Color(hex: "#F59E0B"), label: "Neutral")
                LegendItem(color: Color(hex: "#EF4444"), label: "Negative")
                LegendItem(color: Color.sottoTertiary, label: "No entry")
            }
            .padding(.top, 4)
        }
    }
}

struct DayCell: View {
    let date: Date
    let valence: Double?

    var cellColor: Color {
        guard let v = valence else { return Color.sottoTertiary }
        if v > 0.3 { return Color(hex: "#10B981") }
        if v < -0.3 { return Color(hex: "#EF4444") }
        return Color(hex: "#F59E0B")
    }

    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 6)
                .fill(valence != nil ? cellColor.opacity(0.75) : Color.sottoTertiary.opacity(0.5))
                .frame(height: 30)

            Text(dayLabel(date))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
        }
    }

    func dayLabel(_ date: Date) -> String {
        let d = Calendar.current.component(.day, from: date)
        return "\(d)"
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.75))
                .frame(width: 14, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Valence Trend (sparkline)
struct ValenceTrendChart: View {
    var entries: [JournalEntry]

    private var values: [Double] {
        Array(entries.prefix(14).map { $0.valence }.reversed())
    }

    private var averageValence: Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(values.isEmpty ? "No entries yet" : "Last \(values.count) entries")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if !values.isEmpty {
                    Text(String(format: "Avg. %.2f", averageValence))
                        .font(.caption2).fontDesign(.rounded)
                        .foregroundStyle(dotColor(averageValence))
                }
            }

            if values.count < 2 {
                Text(values.isEmpty ? "No data yet." : "Need more entries for trend.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let step = w / CGFloat(values.count - 1)

                    ZStack {
                        // Zero line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h / 2))
                            path.addLine(to: CGPoint(x: w, y: h / 2))
                        }
                        .stroke(Color.sottoTertiary, style: StrokeStyle(lineWidth: 1, dash: [4]))

                        // Trend line
                        Path { path in
                            for (i, value) in values.enumerated() {
                                let x = CGFloat(i) * step
                                let y = h / 2 - (CGFloat(value) * h / 2 * 0.85)
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [Color.sottoAccent, Color.sottoAccent.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )

                        // Data points
                        ForEach(Array(values.enumerated()), id: \.offset) { i, value in
                            let x = CGFloat(i) * step
                            let y = h / 2 - (CGFloat(value) * h / 2 * 0.85)
                            Circle()
                                .fill(dotColor(value))
                                .frame(width: 7, height: 7)
                                .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 80)
            }
        }
    }

    func dotColor(_ v: Double) -> Color {
        if v > 0.3 { return Color(hex: "#10B981") }
        if v < -0.3 { return Color(hex: "#EF4444") }
        return Color(hex: "#F59E0B")
    }
}

// MARK: - Emotion breakdown (horizontal bar chart)
struct EmotionBreakdownView: View {
    var entries: [JournalEntry]
    
    private var emotions: [(String, Color, Double)] {
        guard !entries.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entry.primaryEmotion, default: 0] += 1
        }
        let total = Double(entries.count)
        return counts.map { (name, count) in
            let color = entries.first(where: { $0.primaryEmotion == name })?.emotionColor ?? .gray
            return (name, color, Double(count) / total)
        }.sorted { $0.2 > $1.2 }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(emotions, id: \.0) { name, color, proportion in
                HStack(spacing: 10) {
                    Text(name)
                        .font(.caption).fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.sottoTertiary).frame(height: 8)
                            Capsule().fill(color.opacity(0.8))
                                .frame(width: geo.size.width * proportion, height: 8)
                                .animation(.spring(duration: 0.7, bounce: 0.2).delay(0.1), value: proportion)
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int(proportion * 100))%")
                        .font(.caption2).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Theme cloud (tag cloud-ish layout)
struct ThemeCloudView: View {
    var entries: [JournalEntry]
    
    private var themes: [(String, Int)] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for theme in entry.themes {
                counts[theme, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(12).map { $0 }
    }

    var body: some View {
        if themes.isEmpty {
            Text("No themes detected yet.")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            let maxCount = Double(themes.first?.1 ?? 1)
            FlexibleTagLayout(spacing: 8) {
                ForEach(themes, id: \.0) { item in
                    Text(item.0)
                        .font(.caption).fontDesign(.rounded)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            Color.sottoAccent.opacity(Double(item.1) / maxCount * 0.3 + 0.05),
                            in: Capsule()
                        )
                        .foregroundStyle(Color.sottoAccent.opacity(Double(item.1) / maxCount * 0.6 + 0.4))
                }
            }
        }
    }
}

// MARK: - Flexible wrapping tag layout
struct FlexibleTagLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.frames[index].origin
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

#Preview("Insights") {
    InsightsView()
        .modelContainer(MockData.previewContainer)
}
#Preview("Insights — dark") {
    InsightsView()
        .modelContainer(MockData.previewContainer)
        .preferredColorScheme(.dark)
}
