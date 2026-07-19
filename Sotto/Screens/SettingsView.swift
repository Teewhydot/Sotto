//
//  SettingsView.swift
//  Sotto
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.date) private var entries: [JournalEntry]

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationTime") private var notificationHour = 21
    @AppStorage("reminderLabel") private var reminderLabel = "Evening"
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("appTheme") private var appTheme = "Indigo"
    @AppStorage("appIcon") private var appIcon = "Default"
    @AppStorage("notificationSound") private var notificationSound = "Whisper"

    @State private var showResetAlert = false
    @State private var showExportSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showReviewAlert = false

    var body: some View {
        NavigationStack {
            List {

                // ── Profile ───────────────────────────────────────────────
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.sottoAccent, Color(hex: "#F2CC8F")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                            Text("IA")
                                .font(.title3).fontWeight(.bold)
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sotto User")
                                .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                            
                            if let firstDate = entries.first?.date {
                                Text("Journalling since \(firstDate.formatted(.dateTime.month().year()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Start your journal today")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }

                // ── Reminders ─────────────────────────────────────────────
                Section("Reminders") {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Daily reminder", systemImage: "bell.fill")
                    }
                    .tint(Color.sottoAccent)

                    if notificationsEnabled {
                        HStack {
                            Label("Reminder time", systemImage: "clock")
                            Spacer()
                            Picker("", selection: $notificationHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)):00 \(hour >= 12 ? "PM" : "AM")")
                                        .tag(hour)
                                }
                            }
                            .tint(.secondary)
                        }

                        HStack {
                            Label("Notification sound", systemImage: "speaker.wave.2")
                            Spacer()
                            Menu(notificationSound) {
                                Button("Whisper") { notificationSound = "Whisper" }
                                Button("Chime") { notificationSound = "Chime" }
                                Button("Subtle") { notificationSound = "Subtle" }
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Appearance ────────────────────────────────────────────
                Section("Appearance") {
                    HStack {
                        Label("Theme", systemImage: "paintpalette")
                        Spacer()
                        Menu(appTheme) {
                            Button("Indigo") { appTheme = "Indigo" }
                            Button("Rose") { appTheme = "Rose" }
                            Button("Slate") { appTheme = "Slate" }
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("App icon", systemImage: "app")
                        Spacer()
                        Menu(appIcon) {
                            Button("Default") { appIcon = "Default" }
                            Button("Dark") { appIcon = "Dark" }
                            Button("Light") { appIcon = "Light" }
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $hapticFeedback) {
                        Label("Haptic feedback", systemImage: "hand.tap.fill")
                    }
                    .tint(Color.sottoAccent)
                }

                // ── Privacy ───────────────────────────────────────────────
                Section("Privacy") {
                    Toggle(isOn: $faceIDEnabled) {
                        Label("Face ID lock", systemImage: "faceid")
                    }
                    .tint(Color.sottoAccent)

                    HStack {
                        Label("Data storage", systemImage: "internaldrive")
                        Spacer()
                        Text("On-device only")
                            .font(.subheadline).foregroundStyle(Color(hex: "#10B981"))
                    }

                    Button {
                        exportData()
                    } label: {
                        Label("Export all entries", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Color.sottoAccent)
                    }
                }

                // ── About ─────────────────────────────────────────────────
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0 (1)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundStyle(.primary)
                    }

                    Button {
                        showReviewAlert = true
                    } label: {
                        Label("Write a review", systemImage: "star.fill")
                            .foregroundStyle(.primary)
                    }
                }

                // ── Danger zone ───────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }

                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete all data?", isPresented: $showResetAlert) {
                Button("Delete", role: .destructive) {
                    do {
                        try modelContext.delete(model: JournalEntry.self)
                    } catch {
                        print("Failed to delete data: \(error)")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently erase every journal entry and insight. This cannot be undone.")
            }
            .alert("Redirect to App Store", isPresented: $showReviewAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This would normally open the App Store review page.")
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(items: [generateExportString()])
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                SafariView(url: URL(string: "https://apple.com/privacy")!)
            }
        }
    }
    
    private func exportData() {
        showExportSheet = true
    }
    
    private func generateExportString() -> String {
        var csv = "Date,Emotion,Summary,Transcript\n"
        for entry in entries {
            let dateStr = entry.date.formatted(date: .abbreviated, time: .shortened)
            let safeSummary = entry.summary.replacingOccurrences(of: "\"", with: "\"\"")
            let safeTranscript = entry.transcript.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(dateStr),\(entry.primaryEmotion),\"\(safeSummary)\",\"\(safeTranscript)\"\n"
        }
        return csv
    }
}

#Preview {
    SettingsView()
}
