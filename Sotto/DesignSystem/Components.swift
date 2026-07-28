import SwiftUI

// MARK: - EmotionBadge
struct EmotionBadge: View {
    let emotion: String
    let color: Color

    var body: some View {
        Text(emotion)
            .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - ThemeChip
struct ThemeChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2).fontDesign(.rounded)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.sottoSecondary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

// MARK: - SectionLabel
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption).fontWeight(.semibold)
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - SottoCard
struct SottoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Color.sottoSecondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - MetricBar
struct MetricBar: View {
    let label: String
    let value: Double     // 0.0–1.0
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sottoTertiary).frame(height: 6)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * value, height: 6)
                        .animation(.spring(duration: 0.6, bounce: 0.2), value: value)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - ValenceBar
struct ValenceBar: View {
    let valence: Double   // -1.0 to 1.0

    var dotColor: Color {
        if valence > 0.3 { return Color(hex: "#10B981") }
        if valence < -0.3 { return Color(hex: "#EF4444") }
        return Color(hex: "#F59E0B")
    }

    var label: String {
        if valence > 0.5 { return "Positive" }
        if valence > 0.1 { return "Slightly positive" }
        if valence > -0.1 { return "Neutral" }
        if valence > -0.5 { return "Slightly negative" }
        return "Negative"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Valence").font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .center) {
                    Capsule()
                        .fill(Color.sottoTertiary)
                        .frame(height: 6)
                    let position = (valence + 1.0) / 2.0
                    Circle()
                        .fill(dotColor)
                        .frame(width: 12, height: 12)
                        .offset(x: (geo.size.width * position) - geo.size.width / 2)
                        .animation(.spring(duration: 0.6, bounce: 0.2), value: valence)
                }
            }
            .frame(height: 12)
            HStack {
                Text("−").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("+").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - MoodDot  (tiny circle for calendar)
struct MoodDot: View {
    let valence: Double

    var color: Color {
        if valence > 0.3 { return Color(hex: "#10B981") }
        if valence < -0.3 { return Color(hex: "#EF4444") }
        return Color(hex: "#F59E0B")
    }

    var body: some View {
        Circle()
            .fill(color.opacity(0.85))
            .frame(width: 6, height: 6)
    }
}

// MARK: - Previews
#Preview {
    VStack(spacing: 16) {
        EmotionBadge(emotion: "Reflective", color: Color(hex: "#F59E0B"))
        ThemeChip(label: "self-doubt")
        SectionLabel(text: "What you said")
        SottoCard {
            Text("Card content").font(.body)
        }
        MetricBar(label: "Intensity", value: 0.7, color: .red)
        ValenceBar(valence: -0.2)
    }
    .padding()
}
