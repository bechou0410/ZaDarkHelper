import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter.
/// Requests auth lazily on first post. Silent-fails if user denies — caller
/// should surface state changes in-app regardless.
enum NotificationService {

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func post(title: String, body: String, identifier: String = UUID().uuidString) async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
