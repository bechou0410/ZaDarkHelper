import AppKit
import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate {

    @MainActor private var appState: AppState?
    @MainActor private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
