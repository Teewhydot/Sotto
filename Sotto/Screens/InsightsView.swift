//
//  InsightsView.swift
//  Sotto
//

import SwiftUI

struct InsightsView: View {
    @State private var selectedPeriod = "Month"
    let periods = ["Week", "Month", "3 Months"]

    // Streak + summary figures
    let currentStreak = 7
    let totalEntries = 32
    let avgWordsPerEntry = 64

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
                            color: Color(hex: "#4F46E5")
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
                            MoodCalendarView()
                        }
                    }

                    // ── Valence trend ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Emotional Tone")
                        SottoCard {
                            ValenceTrendChart()
                        }
                    }

                    // ── Emotion breakdown ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Emotions This Period")
                        SottoCard {
                            EmotionBreakdownView()
                        }
                    }

                    // ── Top themes ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Recurring Themes")
                        SottoCard {
                            ThemeCloudView()
                        }
                    }

                    // ── Weekly brief summary ──────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "This Week")
                        SottoCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.sottoAccent)
                                    Text("Pattern")
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(Color.sottoAccent)
                                }
                                Text(mockWeeklyBrief.patternObservation)
                                    .font(.callout).fontDesign(.rounded)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)

                                Divider()

                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(Color(hex: "#F59E0B"))
                                    Text("Invitation")
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(Color(hex: "#F59E0B"))
                                }
                                Text(mockWeeklyBrief.invitation)
                                    .font(.callout).fontDesign(.rounded).italic()
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
                            }
                        }
                    }

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
    // Sort calendar data by date descending
    private var calendarDays: [(date: Date, valence: Double?)] {
        (0..<30).compactMap { daysAgo -> (Date, Double?)? in
            guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else { return nil }
            let key = mockCalendarData.first(where: { Calendar.current.isDate($0.key, inSameDayAs: date) })
            return (date, key?.value ?? nil)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Day labels
            HStack(spacing: 0) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
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
    // Sample valence over time (most recent 14 entries)
    private let values: [Double] = [-0.2, 0.8, -0.6, 0.65, -0.75, -0.5, 0.9, 0.3, -0.4, 0.6, -0.3, 0.7, -0.8, 0.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Annotation
            HStack {
                Text("Last 14 entries")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("Avg. −0.12")
                    .font(.caption2).fontDesign(.rounded)
                    .foregroundStyle(Color(hex: "#F59E0B"))
            }

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
                            colors: [Color(hex: "#4F46E5"), Color(hex: "#8B5CF6")],
                            startPoint: .leading,
                            endPoint: .trailing
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

    func dotColor(_ v: Double) -> Color {
        if v > 0.3 { return Color(hex: "#10B981") }
        if v < -0.3 { return Color(hex: "#EF4444") }
        return Color(hex: "#F59E0B")
    }
}

// MARK: - Emotion breakdown (horizontal bar chart)
struct EmotionBreakdownView: View {
    private let emotions: [(String, Color, Double)] = [
        ("Reflective",  Color(hex: "#F59E0B"), 0.28),
        ("Overwhelmed", Color(hex: "#374151"), 0.20),
        ("Grateful",    Color(hex: "#10B981"), 0.18),
        ("Anxious",     Color(hex: "#F97316"), 0.16),
        ("Content",     Color(hex: "#34D399"), 0.10),
        ("Excited",     Color(hex: "#10B981"), 0.08),
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(emotions, id: \.0) { name, color, proportion in
                HStack(spacing: 10) {
                    Text(emotionEmoji(for: name))
                        .font(.body)
                        .frame(width: 24)

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
    private let themes: [(String, Int)] = [
        ("work", 12), ("self-doubt", 9), ("communication", 7),
        ("relationships", 6), ("rest", 5), ("gratitude", 5),
        ("anxiety", 4), ("growth", 4), ("creativity", 3),
        ("boundaries", 3), ("family", 2), ("nature", 2)
    ]

    var body: some View {
        FlexibleTagLayout(spacing: 8) {
            ForEach(themes, id: \.0) { item in
                Text(item.0)
                    .font(.caption).fontDesign(.rounded)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(
                        Color.sottoAccent.opacity(Double(item.1) / 14.0 * 0.3 + 0.05),
                        in: Capsule()
                    )
                    .foregroundStyle(Color.sottoAccent.opacity(Double(item.1) / 14.0 * 0.6 + 0.4))
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
}
#Preview("Insights — dark") {
    InsightsView()
        .preferredColorScheme(.dark)
}
