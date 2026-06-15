import Foundation
import UserNotifications
import InboundAdapters
import Errors

final class HealthNotificationCenter: NSObject, HealthNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "vitalserver-helper-health-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
