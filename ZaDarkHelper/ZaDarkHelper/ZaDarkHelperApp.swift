import AppKit
import SwiftUI
import UserNotifications

/// App entry point. Menu-bar only (LSUIElement=YES in Info.plist).
///
/// Previously used SwiftUI `MenuBarExtra`, but that API can't split left-click
/// vs right-click actions. Now routes through an `NSApplicationDelegate` that
/// owns a `StatusBarController` — left-click opens popover, right-click shows
/// a native NSMenu with "Kiểm tra cập nhật" + "Thoát".
@main
struct ZaDarkHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Minimal hidden settings scene so SwiftUI's App protocol is satisfied.
        // All actual UI lives in the NSPopover owned by StatusBarController.
        Settings {
            EmptyView()
        }
    }
}

/// Owns shared state + the menu-bar controller. Created by `NSApplicationDelegateAdaptor`
/// so the NSStatusItem is armed as soon as the app launches (no user click needed).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    @MainActor private var appState: AppState?
    @MainActor private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Become the notification delegate so we can receive action callbacks
        // (e.g. the "Hoàn tác" button on the rename toast).
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            let state = AppState()
            self.appState = state
            self.statusBar = StatusBarController(appState: state)

            // Arm watchers + first refresh + helper update check — does NOT wait
            // for the user to open the popover.
            state.start()
        }
    }

    /// Closing the (nonexistent) window shouldn't quit the menu-bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even when app is foreground (we're a menu-bar app — no
    /// "foreground" in the usual sense, but this keeps behavior consistent).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Routes notification actions back to AppState. Currently only the rename
    /// undo action — but extensible for future actions on the same delegate.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        Task { @MainActor in
            if action == NotificationService.undoActionID,
               let path = userInfo[NotificationService.Keys.currentPath] as? String,
               let originalName = userInfo[NotificationService.Keys.originalName] as? String {
                self.appState?.undoRename(currentPath: path, originalName: originalName)
            }
            completionHandler()
        }
    }
}
