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

    private static let reminderBodies = [
        "How did today actually feel? Say it out loud — Sotto will listen.",
        "A minute of honesty beats an hour of scrolling.",
        "Your future self would love to hear about today.",
    ]
}
