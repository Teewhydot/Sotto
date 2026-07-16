//
//  TodayView.swift
//  Sotto
//

import SwiftUI

struct TodayView: View {
    @Binding var showRecording: Bool
    @State private var showBrief = false
    @State private var showTextEntry = false
    let todayEntry = mockEntries[0]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Date & greeting ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.title2).fontWeight(.semibold).fontDesign(.rounded)

                        Text(greetingText())
                            .font(.body).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // ── CTA cards ───────────────────────────────────────────
                    VStack(spacing: 10) {
                        Button { showRecording = true } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.2))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                Text("Start speaking")
                                    .fontWeight(.semibold).fontDesign(.rounded)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).fontWeight(.semibold)
                                    .opacity(0.6)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#6366F1"), Color(hex: "#4338CA")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Button {
                            showTextEntry = true
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.sottoSecondary)
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text("Type instead")
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(Color.sottoSecondary, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    // ── Today's entry ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Today's Entry")

                        NavigationLink(destination: EntryDetailView(entry: todayEntry)) {
                            SottoCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .center) {
                                        EmotionBadge(
                                            emotion: todayEntry.primaryEmotion,
                                            color: todayEntry.emotionColor
                                        )
                                        Spacer()
                                        Label(todayEntry.duration, systemImage: "clock")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }

                                    Text(String(todayEntry.transcript.prefix(120)) + "…")
                                        .font(.callout).fontDesign(.serif)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(4)
                                        .multilineTextAlignment(.leading)

                                    // Theme chips
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(todayEntry.themes.prefix(3), id: \.self) { theme in
                                                ThemeChip(label: theme)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Weekly brief ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "This Week's Brief")

                        SottoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.sottoAccent)
                                    Text("Week of \(weekStartString())")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    EmotionBadge(
                                        emotion: mockWeeklyBrief.dominantEmotion,
                                        color: Color(hex: "#F59E0B")
                                    )
                                }

                                Text(
                                    showBrief
                                        ? mockWeeklyBrief.narrative
                                        : String(mockWeeklyBrief.narrative.prefix(90)) + "…"
                                )
                                .font(.callout).fontDesign(.rounded)
                                .foregroundStyle(.primary)
                                .lineSpacing(4)
                                .animation(.easeInOut(duration: 0.3), value: showBrief)

                                Button {
                                    withAnimation { showBrief.toggle() }
                                } label: {
                                    Text(showBrief ? "Show less" : "Read more →")
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(Color.sottoAccent)
                                }

                                if showBrief {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(mockWeeklyBrief.patternObservation)
                                            .font(.caption).fontDesign(.rounded)
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(3)

                                        Divider()

                                        Text(mockWeeklyBrief.invitation)
                                            .font(.callout).fontDesign(.rounded).italic()
                                            .foregroundStyle(.primary)
                                            .lineSpacing(3)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }

                    // ── Streak / stats strip ─────────────────────────────────
                    HStack(spacing: 12) {
                        StatPill(value: "5", label: "This week", icon: "flame.fill", color: Color(hex: "#F97316"))
                        StatPill(value: "7", label: "Day streak", icon: "bolt.fill", color: Color(hex: "#4F46E5"))
                        StatPill(value: "32", label: "All entries", icon: "text.bubble.fill", color: Color(hex: "#10B981"))
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("sotto")
                        .font(.headline).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundStyle(Color.sottoAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showTextEntry) {
            TextEntryView()
        }
    }

    // MARK: - Helpers
    func greetingText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "Good morning."
        case 11..<17: return "How's your afternoon?"
        case 17..<21: return "Good evening."
        default: return "Still awake."
        }
    }

    func weekStartString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        guard let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) else { return "" }
        return formatter.string(from: weekStart)
    }
}

// MARK: - Stat pill
struct StatPill: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(color)
            Text(value)
                .font(.title3).fontWeight(.bold).fontDesign(.rounded)
            Text(label)
                .font(.caption2).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.sottoSecondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Scale press button style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview("Today — light") {
    TodayView(showRecording: .constant(false))
}
#Preview("Today — dark") {
    TodayView(showRecording: .constant(false))
        .preferredColorScheme(.dark)
}
