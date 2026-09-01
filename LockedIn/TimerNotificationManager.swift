import Foundation
import UserNotifications

enum TimerNotificationManager {
    static let identifier = "lockedin.rest-timer"

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func schedule(endDate: Date) {
        requestAuthorizationIfNeeded()
        cancel()

        let interval = max(1, endDate.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei"
        content.body = "Zeit für den nächsten Satz."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
