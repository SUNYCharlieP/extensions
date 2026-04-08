import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let lastNotifiedKey = "arca_last_notified_trending"

    private init() {}

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Check for breaking stories (5+ sources) and send a notification if new.
    func checkForBreakingStories(_ items: [FeedItem]) {
        let breaking = items.filter { $0.sourceCount >= 5 }
        guard let top = breaking.first else { return }

        let lastNotified = defaults.string(forKey: lastNotifiedKey) ?? ""
        let storyKey = top.title.prefix(50).lowercased()

        guard storyKey != lastNotified else { return }
        defaults.set(storyKey, forKey: lastNotifiedKey)

        let content = UNMutableNotificationContent()
        content.title = "Breaking: \(top.sourceCount) sources"
        content.body = top.title
        content.sound = .default
        content.categoryIdentifier = "BREAKING_STORY"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "breaking-\(storyKey.hashValue)", content: content, trigger: trigger)

        center.add(request)
    }
}
