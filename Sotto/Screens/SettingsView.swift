import SwiftUI
import SwiftData
import StoreKit
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \JournalEntry.date) private var entries: [JournalEntry]

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationTime") private var notificationHour = 21
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("appIcon") private var appIcon = "Default"
    @AppStorage("userDisplayName") private var userDisplayName = "Sotto User"
    @AppStorage("notificationSound") private var notificationSound = "Whisper"

    @State private var showResetAlert = false
    @State private var showExportSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showEditProfile = false
    @State private var nameDraft = ""
    @State private var faceIDUnavailableMessage: String?

    let notificationSounds = ["Whisper", "Chime", "Subtle"]
    let iconOptions = ["Default", "Dark", "Light"]

    var body: some View {
        NavigationStack {
            List {
                profileSection
                remindersSection
                appearanceSection
                privacySection
                aboutSection
                dangerSection
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
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(items: [generateExportString()])
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                NavigationStack { PrivacyPolicyView() }
            }
            .alert("Edit profile", isPresented: $showEditProfile) {
                TextField("Name", text: $nameDraft)
                Button("Save") {
                    let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { userDisplayName = trimmed }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Face ID unavailable",
                isPresented: Binding(
                    get: { faceIDUnavailableMessage != nil },
                    set: { if !$0 { faceIDUnavailableMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(faceIDUnavailableMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var profileSection: some View {
        Section {
            Button {
                nameDraft = userDisplayName
                showEditProfile = true
            } label: {
                HStack(spacing: 14) {
                    avatarView
                    VStack(alignment: .leading, spacing: 3) {
                        Text(userDisplayName)
                            .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                            .foregroundStyle(.primary)
                        memberSinceText
                    }
                    Spacer()
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.sottoAccent, themeManager.current.warm],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
            Text(profileInitials)
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var memberSinceText: some View {
        if let firstDate = entries.first?.date {
            Text("Journalling since \(firstDate.formatted(.dateTime.month().year()))")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Start your journal today")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            Toggle(isOn: $notificationsEnabled) {
                Label("Daily reminder", systemImage: "bell.fill")
            }
            .tint(Color.sottoAccent)
            .onChange(of: notificationsEnabled) { _, enabled in
                Task { await handleReminderToggle(enabled) }
            }

            if notificationsEnabled {
                reminderTimeRow
                reminderSoundRow
            }
        }
    }

    private var reminderTimeRow: some View {
        HStack {
            Label("Reminder time", systemImage: "clock")
            Spacer()
            Picker("", selection: $notificationHour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(Self.hourFormatter(hour)).tag(hour)
                }
            }
            .tint(.secondary)
            .onChange(of: notificationHour) { _, newHour in
                Task { await rescheduleReminders(hour: newHour) }
            }
        }
    }

    private var reminderSoundRow: some View {
        HStack {
            Label("Notification sound", systemImage: "speaker.wave.2")
            Spacer()
            Menu(notificationSound) {
                ForEach(notificationSounds, id: \.self) { sound in
                    Button(sound) {
                        notificationSound = sound
                        Task { await rescheduleReminders(hour: notificationHour) }
                    }
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Label("Theme", systemImage: "paintpalette")
                Spacer()
                Menu(themeManager.current.id) {
                    ForEach(Theme.all) { theme in
                        Button(theme.id) {
                            Haptics.tap()
                            themeManager.select(theme)
                        }
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack {
                Label("App icon", systemImage: "app")
                Spacer()
                Menu(appIcon) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button(icon) { setAppIcon(icon) }
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }

            Toggle(isOn: $hapticFeedback) {
                Label("Haptic feedback", systemImage: "hand.tap.fill")
            }
            .tint(Color.sottoAccent)
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Toggle(isOn: $faceIDEnabled) {
                Label("Face ID lock", systemImage: "faceid")
            }
            .tint(Color.sottoAccent)
            .onChange(of: faceIDEnabled) { _, enabled in
                if enabled { validateBiometricAvailability() }
            }

            if faceIDEnabled {
                Text("Sotto locks whenever it leaves the foreground. Unlock with Face ID or your device passcode.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Button {
                showPrivacyPolicy = true
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundStyle(.primary)
            }

            Button {
                requestReview()
            } label: {
                Label("Write a review", systemImage: "star.fill")
                    .foregroundStyle(.primary)
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Delete all data", systemImage: "trash")
            }
        }
    }

    // MARK: - Profile

    private var profileInitials: String {
        let words = userDisplayName.split(separator: " ")
        let initials = words.prefix(2).compactMap(\.first)
        return initials.map(String.init).joined().uppercased()
    }

    // MARK: - Reminders

    private func handleReminderToggle(_ enabled: Bool) async {
        if enabled {
            await rescheduleReminders(hour: notificationHour)
        } else {
            NotificationManager.shared.cancelDailyReminder()
        }
    }

    private func rescheduleReminders(hour: Int) async {
        let granted = await NotificationManager.shared.scheduleDailyReminder(hour: hour, soundName: notificationSound)
        if !granted {
            notificationsEnabled = false
        }
    }

    // MARK: - Face ID validation

    /// Refuse to enable the lock on devices with no usable auth method,
    /// otherwise the user would lock themselves out permanently.
    private func validateBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            faceIDEnabled = false
            faceIDUnavailableMessage =
                error?.localizedDescription
                ?? "This device has no Face ID or passcode configured, so the app lock cannot be enabled."
            return
        }
    }

    // MARK: - App icon

    private func setAppIcon(_ name: String) {
        appIcon = name
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target: String? = (name == "Default") ? nil : name
        UIApplication.shared.setAlternateIconName(target) { _ in
            // Icon swap failures (e.g. provisioning limitations) keep Default.
        }
    }

    // MARK: - Version

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Export

    private func exportData() {
        Haptics.tap()
        showExportSheet = true
    }

    private func generateExportString() -> String {
        var csv = "Date,Mode,Emotion,Summary,Note,Transcript\n"
        for entry in entries {
            func escape(_ field: String) -> String {
                "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            let dateStr = entry.date.formatted(date: .abbreviated, time: .shortened)
            csv += [
                dateStr,
                entry.inputMode,
                entry.primaryEmotion,
                escape(entry.summary),
                escape(entry.note),
                escape(entry.transcript),
            ].joined(separator: ",") + "\n"
        }
        return csv
    }

    static func hourFormatter(_ hour: Int) -> String {
        "\(hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)):00 \(hour >= 12 ? "PM" : "AM")"
    }
}

#Preview {
    SettingsView()
        .modelContainer(MockData.previewContainer)
}
