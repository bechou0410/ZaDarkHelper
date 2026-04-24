import AppKit
import Foundation

/// Reliable Zalo launcher using `NSWorkspace.openApplication(at:configuration:)`.
/// The legacy `NSWorkspace.shared.open(URL)` is known to silently no-op on
/// macOS 14+ for bundles. This wrapper adapts the completion-handler API to
/// async/await — no semaphore, no actor-blocking, safe to call from any
/// isolation (including an actor's rePatch flow).
enum ZaloLauncher {

    @discardableResult
    static func launch() async -> Bool {
        let url = URL(fileURLWithPath: ZaloVersionProbe.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.promptsUserIfNeeded = true

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                cont.resume(returning: error == nil)
            }
        }
    }
}
