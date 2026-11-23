import Foundation
import UserNotifications

/// Rappels locaux programmés par le site : cours (10 min avant), devoirs (la veille), tenue (la veille).
/// Tout reste sur le téléphone : aucun serveur de notifications n'est utilisé.
enum Reminders {
    private static let idPrefix = "edp."

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    /// Remplace tous les rappels EDP en attente par la nouvelle liste.
    static func schedule(_ items: [[String: Any]], _ done: @escaping (Int) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map { $0.identifier }.filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            let now = Date()
            var count = 0

            for item in items.prefix(60) {   // iOS garde au plus 64 rappels en attente
                guard let id = item["id"] as? String,
                      let title = item["title"] as? String,
                      let dateString = item["date"] as? String,
                      let date = withFraction.date(from: dateString) ?? plain.date(from: dateString),
                      date > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = (item["body"] as? String) ?? ""
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: idPrefix + id, content: content, trigger: trigger))
                count += 1
            }
            DispatchQueue.main.async { done(count) }
        }
    }
}
