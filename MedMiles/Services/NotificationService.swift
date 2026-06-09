import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let remindersEnabledKey = "taxDeadlineRemindersEnabled"

    var isRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: remindersEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: remindersEnabledKey) }
    }

    private init() {}

    // MARK: - Permission

    func requestPermission() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                // Non-critical: permission request is best-effort
            }
        }
    }

    // MARK: - Schedule Quarterly Reminders

    /// Schedules 30-day and 7-day reminders for each quarterly tax deadline.
    /// - Parameter taxYear: The tax year to schedule reminders for.
    func scheduleQuarterlyReminders(for taxYear: Int) {
        guard isRemindersEnabled else { return }

        // Cancel existing reminders first to avoid duplicates
        cancelAllReminders()

        let deadlines: [(quarter: String, month: Int, day: Int, year: Int)] = [
            ("1", 4, 15, taxYear),       // Q1: April 15
            ("2", 6, 15, taxYear),       // Q2: June 15
            ("3", 9, 15, taxYear),       // Q3: September 15
            ("4", 1, 15, taxYear + 1)    // Q4: January 15 next year
        ]

        for deadline in deadlines {
            let deadlineDateString = formattedDate(month: deadline.month, day: deadline.day, year: deadline.year)

            // 30-day reminder
            if let reminderComponents = dateComponents(bySubtractingDays: 30, fromMonth: deadline.month, day: deadline.day, year: deadline.year) {
                let id = "tax-reminder-Q\(deadline.quarter)-\(deadline.year)-30d"
                let body = "Your Q\(deadline.quarter) estimated tax payment is due in 30 days on \(deadlineDateString). Open MedMiles to review your estimate."
                scheduleNotification(identifier: id, title: "Quarterly Tax Payment Due Soon", body: body, dateComponents: reminderComponents)
            }

            // 7-day reminder
            if let reminderComponents = dateComponents(bySubtractingDays: 7, fromMonth: deadline.month, day: deadline.day, year: deadline.year) {
                let id = "tax-reminder-Q\(deadline.quarter)-\(deadline.year)-7d"
                let body = "Your Q\(deadline.quarter) estimated tax payment is due in 7 days on \(deadlineDateString). Don't forget to make your payment!"
                scheduleNotification(identifier: id, title: "Quarterly Tax Payment Due Soon", body: body, dateComponents: reminderComponents)
            }
        }
    }

    // MARK: - Cancel

    func cancelAllReminders() {
        // Remove only tax-reminder notifications (not others the app may schedule)
        center.getPendingNotificationRequests { requests in
            let taxIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("tax-reminder-") }
            self.center.removePendingNotificationRequests(withIdentifiers: taxIds)
        }
    }

    /// Remove ALL pending notifications (used during account deletion).
    func removeAllReminders() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    private func scheduleNotification(identifier: String, title: String, body: String, dateComponents: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { _ in
            // Non-critical: notification scheduling is best-effort
        }
    }

    /// Returns `DateComponents` (year, month, day, hour=9, minute=0) for a date that is
    /// `days` before the given month/day/year. Notifications fire at 9:00 AM local time.
    private func dateComponents(bySubtractingDays days: Int, fromMonth month: Int, day: Int, year: Int) -> DateComponents? {
        var calendar = Calendar.current
        calendar.timeZone = .current

        var base = DateComponents()
        base.year = year
        base.month = month
        base.day = day

        guard let baseDate = calendar.date(from: base),
              let reminderDate = calendar.date(byAdding: .day, value: -days, to: baseDate) else {
            return nil
        }

        // Only schedule if the reminder date is in the future
        guard reminderDate > Date() else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = 9
        components.minute = 0
        return components
    }

    /// Formats a month/day/year into a human-readable string like "April 15, 2026".
    private func formattedDate(month: Int, day: Int, year: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(month)/\(day)/\(year)"
    }
}
