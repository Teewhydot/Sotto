import Foundation
import UserNotifications

// MARK: - Daily reminder scheduling

final class NotificationManager {
    static let shared = NotificationManager()
    private static let reminderIdentifier = "ng.com.sirteefyapps.Sotto.dailyReminder"

    private var center: UNUserNotificationCenter { .current() }

    /// Requests authorization. Returns false if denied.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Schedules (replacing any previous) a repeating daily reminder at `hour`.
    /// - Parameter soundName: Preferred notification sound. Custom sounds require
    ///   bundled .caf/.aiff files in the app bundle; until those are added the
    ///   system default sound is used for every option (placeholder).
    @discardableResult
    func scheduleDailyReminder(hour: Int, soundName: String) async -> Bool {
        guard await requestAuthorization() else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])

        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "A moment for yourself"
        content.body = Self.reminderBodies.randomElement() ?? "Take a quiet minute to check in with yourself."
        // Placeholder: swap in custom UNNotificationSound(named:) once sound
        // assets ("Whisper", "Chime", "Subtle") are bundled with the app.
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }

    // MARK: - Trial ending reminder

    private static let trialReminderIdentifier = "ng.com.sirteefyapps.Sotto.trialEnding"

    /// Schedules a one-shot reminder ~2 days before a free trial converts.
    /// Deliberately states the charge plainly rather than pitching: a
    /// surprise charge is the single fastest way to earn a refund request
    /// and a one-star review, and Apple's own pre-trial reminder is not
    /// something to rely on as the user's only warning.
    ///
    /// Purely local — derived from the entitlement's expiry date, no server
    /// and no tracking involved.
    @discardableResult
    func scheduleTrialEndingReminder(trialEnds: Date, priceDescription: String) async -> Bool {
        cancelTrialEndingReminder()
        guard await requestAuthorization() else { return false }

        let fireDate = Calendar.current.date(byAdding: .day, value: -2, to: trialEnds) ?? trialEnds
        // Nothing to schedule if that moment has already passed.
        guard fireDate > .now else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Your Sotto trial ends soon"
        content.body = "You'll be charged \(priceDescription) on \(Self.trialDateFormatter.string(from: trialEnds)) unless you cancel in App Store settings."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.trialReminderIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelTrialEndingReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.trialReminderIdentifier])
    }

    private static let trialDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let reminderBodies = [
        "How did today actually feel? Say it out loud — Sotto will listen.",
        "A minute of honesty beats an hour of scrolling.",
        "Your future self would love to hear about today.",
    ]
}
