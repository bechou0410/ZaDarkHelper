import AppKit
import Foundation

/// Observes NSWorkspace notifications so the app can react when Zalo launches
/// or quits. Fires `onZaloLaunch` opportunistically so we can re-read Zalo's
/// Info.plist in case the user opened a freshly-updated Zalo without us
/// catching an FSEvent. `onZaloQuit` is used by `DeferredUpdateManager` (F3)
/// to install a pre-downloaded helper update when Zalo exits.
final class WorkspaceObserver: @unchecked Sendable {

    var onZaloLaunch: (@Sendable () -> Void)?
    var onZaloQuit: (@Sendable () -> Void)?
    var onWake: (@Sendable () -> Void)?

    private var launchToken: NSObjectProtocol?
    private var terminateToken: NSObjectProtocol?
    private var wakeToken: NSObjectProtocol?

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        launchToken = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            if Self.isZalo(bundleID: id) {
                self?.onZaloLaunch?()
            }
        }

        terminateToken = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            if Self.isZalo(bundleID: id) {
                self?.onZaloQuit?()
            }
        }

        wakeToken = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onWake?()
        }
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        if let t = launchToken { nc.removeObserver(t) }
        if let t = terminateToken { nc.removeObserver(t) }
        if let t = wakeToken { nc.removeObserver(t) }
        launchToken = nil
        terminateToken = nil
        wakeToken = nil
    }

    private static func isZalo(bundleID: String) -> Bool {
        bundleID == ZaloVersionProbe.bundleIDFallback
            || bundleID.lowercased().contains("zalo")
    }

    deinit { stop() }
}
