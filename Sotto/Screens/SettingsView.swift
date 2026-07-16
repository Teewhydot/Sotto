//
//  SettingsView.swift
//  Sotto
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationTime") private var notificationHour = 21
    @AppStorage("reminderLabel") private var reminderLabel = "Evening"
    @AppStorage("hapticFeedback") private var hapticFeedback = true

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
                                        colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
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
                            Text("Issa Abubakar")
                                .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                            Text("Journalling since July 2025")
                                .font(.caption).foregroundStyle(.secondary)
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
                            Text("9:00 PM")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("Notification sound", systemImage: "speaker.wave.2")
                            Spacer()
                            Text("Whisper")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Appearance ────────────────────────────────────────────
                Section("Appearance") {
                    HStack {
                        Label("Theme", systemImage: "paintpalette")
                        Spacer()
                        Text("Indigo")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("App icon", systemImage: "app")
                        Spacer()
                        Text("Default")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $hapticFeedback) {
                        Label("Haptic feedback", systemImage: "hand.tap.fill")
                    }
                    .tint(Color.sottoAccent)
                }

                // ── Privacy ───────────────────────────────────────────────
                Section("Privacy") {
                    HStack {
                        Label("Face ID lock", systemImage: "faceid")
                        Spacer()
                        Text("Off")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Data storage", systemImage: "internaldrive")
                        Spacer()
                        Text("On-device only")
                            .font(.subheadline).foregroundStyle(Color(hex: "#10B981"))
                    }

                    Button {
                        showExportSheet = true
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

                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(Color.sottoAccent)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete all data?", isPresented: $showResetAlert) {
                Button("Delete", role: .destructive) {}
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
                ShareSheet(items: ["Date,Emotion,Transcript\n2026-07-16,Positive,Sample transcript data..."])
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                SafariView(url: URL(string: "https://apple.com/privacy")!)
            }
        }
    }
}

#Preview {
    SettingsView()
}
