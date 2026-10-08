import UserNotifications

/// 毎週日曜の夜に「週次レポートを作りましょう」と通知する。
enum ReportReminder {
    private static let identifier = "weeklyReportReminder"

    static func setEnabled(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return false }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }

        let content = UNMutableNotificationContent()
        content.title = "今週の振り返り"
        content.body = "アプリの「レポート」タブから、今週の週次レポートを作成しましょう。"
        content.sound = .default
        // 日曜（weekday = 1）の 20:00。
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 0, weekday: 1), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }
}
