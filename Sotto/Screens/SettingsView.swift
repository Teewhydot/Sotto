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
    @State private var showEditProfile = false
    @State private var nameDraft = ""
    @State private var pendingRemoval: RemovalTarget?

    /// One sheet at a time, from one place. Separate `.sheet` modifiers —
    /// especially stacked on the same view, or attached to a `Section`
    /// inside the `List` — fight over the same presentation host: UIKit
    /// rejects the second with "presenting while a presentation is in
    /// progress" and SwiftUI resolves it by tearing the new sheet straight
    /// back down (the "opens then instantly closes, works on the second
    /// tap" bug).
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: String, Identifiable {
        case export, privacyPolicy, paywall, subscription
        var id: String { rawValue }
    }

    private enum RemovalTarget {
        case whisper
        case insight
    }

    let notificationSounds = ["Whisper", "Chime", "Subtle"]
    let iconOptions = ["Default", "Dark", "Light"]

    var body: some View {
        NavigationStack {
            List {
                profileSection
                remindersSection
                appearanceSection
                modelsSection
                privacySection
                aboutSection
                dangerSection
            }
            // Keep the last rows (Delete all data) clear of the floating
            // custom tab bar (~66 pt tall) overlaying this screen.
            .contentMargins(.bottom, 88, for: .scrollContent)
            .confirmationDialog(
                "Remove transcription model?",
                isPresented: Binding(
                    get: { pendingRemoval == .whisper },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    ModelLibrary.shared.deleteWhisperModels()
                    FeedbackCenter.shared.success(
                        "Transcription model removed",
                        detail: "Dictation will use Apple's recognizer until it re-downloads."
                    )
                }
            } message: {
                Text("Dictation will fall back to Apple's speech recognizer. The model re-downloads next time you record.")
            }
            .confirmationDialog(
                "Remove insights model?",
                isPresented: Binding(
                    get: { pendingRemoval == .insight },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        await ModelLibrary.shared.deleteInsightModel()
                        FeedbackCenter.shared.success(
                            "Insights model removed",
                            detail: "Insights will use on-device heuristics until it re-downloads."
                        )
                    }
                }
            } message: {
                Text("Insights and transcript cleanup will use simpler on-device heuristics. The model re-downloads next time it's needed.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete all data?", isPresented: $showResetAlert) {
                Button("Delete", role: .destructive) {
                    do {
                        try modelContext.delete(model: JournalEntry.self)
                        try modelContext.save()
                        FeedbackCenter.shared.success("All data deleted")
                    } catch {
                        modelContext.rollback()
                        FeedbackCenter.shared.error("Couldn't delete your data", error)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently erase every journal entry and insight. This cannot be undone.")
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .export:
                    ShareSheet(items: [generateExportString()])
                case .privacyPolicy:
                    NavigationStack { PrivacyPolicyView() }
                case .paywall:
                    PremiumPaywallView(onComplete: { activeSheet = nil })
                case .subscription:
                    SubscriptionDetailView()
                }
            }
            .alert("Edit profile", isPresented: $showEditProfile) {
                TextField("Name", text: $nameDraft)
                Button("Save") {
                    let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { userDisplayName = trimmed }
                }
                Button("Cancel", role: .cancel) {}
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

    // MARK: On-device models

    private var modelsSection: some View {
        Section("On-Device Models") {
            let library = ModelLibrary.shared

            // Involuntary churn — a failed card the user never noticed — is
            // a meaningful share of subscription losses. Surfacing it where
            // they can act beats silently letting access lapse.
            if case .billingIssue = PremiumManager.shared.subscriptionStatus {
                Button {
                    activeSheet = .subscription
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(hex: "#F59E0B"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Payment problem")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("Update your payment method to keep Smart Insights.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            modelRow(
                title: "Transcription",
                subtitle: "On-device speech-to-text",
                isCached: library.whisperCached,
                sizeBytes: library.whisperSizeBytes,
                isBusy: false,
                removeTarget: .whisper,
                downloadAction: nil
            )

            modelRow(
                title: "Smart Insights",
                subtitle: "Transcript cleanup & reflections",
                isCached: library.isInsightDownloading || library.insightCached || library.insightReady,
                sizeBytes: library.insightSizeBytes,
                isBusy: library.isInsightDownloading,
                removeTarget: .insight,
                isLocked: !library.isInsightEntitled,
                downloadAction: { Task { await library.downloadInsightModel() } }
            )

            if library.isInsightEntitled {
                Button {
                    activeSheet = .subscription
                } label: {
                    HStack {
                        Text("Manage Subscription")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(
        title: String,
        subtitle: String,
        isCached: Bool,
        sizeBytes: Int64,
        isBusy: Bool,
        removeTarget: RemovalTarget,
        isLocked: Bool = false,
        downloadAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body).fontDesign(.rounded)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if isBusy {
                Text("\(Int(((ModelLibrary.shared.insightDownloadProgress ?? 0) * 100).rounded()))%")
                    .font(.caption).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(Color.sottoAccent)
            } else if isLocked {
                // Checked before isCached: leftover cached files (a lapsed
                // subscription, or dev-testing residue) don't make the
                // feature usable — LocalInsightEngine.prepare() still gates
                // actually loading them.
                Label("Premium", systemImage: "lock.fill")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            } else if isCached {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color(hex: "#10B981"))
            } else {
                Text("Not downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if isBusy {
            HStack(spacing: 10) {
                ProgressView(value: ModelLibrary.shared.insightDownloadProgress ?? 0)
                    .tint(Color.sottoAccent)
                if let bytes = sizeBytes > 0 ? sizeBytes : nil {
                    Text(ModelLibrary.formattedSize(bytes))
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        } else if isLocked {
            Button {
                activeSheet = .paywall
            } label: {
                HStack {
                    Text("Unlock Smart Insights")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .foregroundStyle(Color.sottoAccent)
            }
        } else if isCached {
            Button(role: .destructive) {
                pendingRemoval = removeTarget
            } label: {
                HStack {
                    Text("Remove model")
                    Spacer()
                    if sizeBytes > 0 {
                        Text(ModelLibrary.formattedSize(sizeBytes))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else if let downloadAction {
            Button {
                downloadAction()
            } label: {
                HStack {
                    Text("Download model")
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                }
                .foregroundStyle(Color.sottoAccent)
            }
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
                activeSheet = .privacyPolicy
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
        guard granted else {
            // Flipping the switch back on its own reads as a broken toggle.
            // The only fix is in iOS Settings, so say that.
            notificationsEnabled = false
            FeedbackCenter.shared.error(
                "Reminders are turned off for Sotto",
                detail: "Allow notifications for Sotto in iOS Settings to get a daily reminder."
            )
            return
        }
        FeedbackCenter.shared.success(
            "Daily reminder set",
            detail: "You'll be nudged at \(Self.hourLabel(hour))."
        )
    }

    /// "9 AM" / "10 PM" — matches the wording of the hour picker.
    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    // MARK: - Face ID validation

    /// Refuse to enable the lock on devices with no usable auth method,
    /// otherwise the user would lock themselves out permanently.
    private func validateBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            faceIDEnabled = false
            FeedbackCenter.shared.error(
                "App lock can't be enabled",
                detail: error?.localizedDescription
                    ?? "This device has no Face ID or passcode configured, so the app lock cannot be enabled."
            )
            return
        }
    }

    // MARK: - App icon

    private func setAppIcon(_ name: String) {
        appIcon = name
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target: String? = (name == "Default") ? nil : name
        UIApplication.shared.setAlternateIconName(target) { error in
            guard let error else { return }
            // The icon silently staying on Default reads as a broken row.
            Task { @MainActor in
                appIcon = "Default"
                FeedbackCenter.shared.error("Couldn't change the app icon", error)
            }
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
        activeSheet = .export
    }

    private func generateExportString() -> String {
        var csv = "Date,Mode,Emotion,Summary,Note,Transcript\n"
        for entry in entries {
            func escape(_ field: String) -> String {
                "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            // Every field is quoted — a locale-formatted date (e.g.
            // "9/4/26, 3:00 PM" in en_US) contains a comma too, and an
            // unescaped one silently shifts every later column in the row.
            let dateStr = entry.date.formatted(date: .abbreviated, time: .shortened)
            csv += [
                escape(dateStr),
                escape(entry.inputMode),
                escape(entry.primaryEmotion),
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
