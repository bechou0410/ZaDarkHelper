import AppKit
import Foundation

/// Reliable Zalo launcher.
/// `NSWorkspace.shared.open(URL)` is legacy and can silently no-op on macOS 14+
/// when the path is a bundle. Use `openApplication(at:configuration:)` instead
/// and wait briefly for the completion handler so we can surface failure state.
enum ZaloLauncher {

    @discardableResult
    static func launch(timeout: TimeInterval = 5.0) -> Bool {
        let url = URL(fileURLWithPath: ZaloVersionProbe.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.promptsUserIfNeeded = true

        let lock = NSLock()
        var success = false
        let sem = DispatchSemaphore(value: 0)

        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            lock.lock()
            success = (error == nil)
            lock.unlock()
            sem.signal()
        }

        _ = sem.wait(timeout: .now() + timeout)
        lock.lock()
        let result = success
        lock.unlock()
        return result
    }
}
