import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter.
/// Requests auth lazily on first post. Silent-fails if user denies — caller
/// should surface state changes in-app regardless.
enum NotificationService {

    // MARK: - Action / category identifiers
    static let renameCategoryID = "zadark.rename"
    static let undoActionID = "zadark.rename.undo"

    /// User-info keys for the rename toast — read by AppDelegate undo handler.
    enum Keys {
        static let originalName = "originalName"   // e.g. "gen-h-foo.jpg"
        static let currentPath = "currentPath"     // absolute path of renamed file
    }

    /// Called once at app launch to register the "Hoàn tác" action button.
    static func registerCategories() {
        let undo = UNNotificationAction(
            identifier: undoActionID,
            title: "Hoàn tác",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: renameCategoryID,
            actions: [undo],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

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

    /// Toast for an automatic rename done by `DownloadFolderWatcher`.
    /// Carries enough user-info for AppDelegate to undo if the user clicks the action.
    static func postRenameToast(originalName: String, fixedURL: URL) async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Đã sửa tên tệp Zalo"
        content.body = fixedURL.lastPathComponent
        content.sound = .default
        content.categoryIdentifier = renameCategoryID
        content.userInfo = [
            Keys.originalName: originalName,
            Keys.currentPath: fixedURL.path
        ]

        let request = UNNotificationRequest(
            identifier: "zadark.rename.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
