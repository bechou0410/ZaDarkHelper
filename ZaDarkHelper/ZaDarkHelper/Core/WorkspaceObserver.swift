import AppKit
import Foundation

/// Observes NSWorkspace notifications so the app can react when Zalo launches.
/// Fires `onZaloLaunch` opportunistically so we can re-read Zalo's Info.plist
/// in case the user opened a freshly-updated Zalo without us catching an FSEvent.
final class WorkspaceObserver: @unchecked Sendable {

    var onZaloLaunch: (@Sendable () -> Void)?
    var onWake: (@Sendable () -> Void)?

    private var launchToken: NSObjectProtocol?
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
            if id == ZaloVersionProbe.bundleIDFallback || id.lowercased().contains("zalo") {
                self?.onZaloLaunch?()
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
        if let t = wakeToken { nc.removeObserver(t) }
        launchToken = nil
        wakeToken = nil
    }

    deinit { stop() }
}
