import CoreServices
import Foundation

/// FSEvents-based watcher on /Applications/Zalo.app.
/// Emits .changed(ZaloInfo) when Info.plist build number differs from last snapshot.
/// Emits .disappeared / .reappeared on bundle removal/recreation.
/// Debounces rapid events by 2s so it sees a settled version, not mid-copy state.
final class ZaloBundleWatcher: @unchecked Sendable {

    enum Event: Sendable, Equatable {
        case changed(ZaloInfo)
        case disappeared
        case reappeared(ZaloInfo)
    }

    var onEvent: (@Sendable (Event) -> Void)?

    private var stream: FSEventStreamRef?
    private var lastInfo: ZaloInfo?
    private var lastBundleExisted: Bool = false
    private let debounceQueue = DispatchQueue(label: "zadark.watcher.debounce")
    private var debounceWorkItem: DispatchWorkItem?
    private var suspended = false

    func start() {
        guard stream == nil else { return }

        lastInfo = ZaloVersionProbe.read()
        lastBundleExisted = lastInfo != nil

        // Watch the parent /Applications directory too — Zalo updates often replace
        // the bundle via rename-in-place which fires parent-level events.
        let paths = [ZaloVersionProbe.bundlePath, "/Applications"] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, clientInfo, numEvents, _, _, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let me = Unmanaged<ZaloBundleWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                me.scheduleRecheck()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(s, debounceQueue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    /// Suspend event emission during self-triggered writes (e.g. our own patch run).
    func setSuspended(_ value: Bool) {
        debounceQueue.async { [weak self] in
            self?.suspended = value
        }
    }

    /// Force an immediate recheck — used by WorkspaceObserver when Zalo launches.
    func recheckNow() {
        debounceQueue.async { [weak self] in
            self?.evaluate()
        }
    }

    // MARK: - Private

    private func scheduleRecheck() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        debounceWorkItem = work
        debounceQueue.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func evaluate() {
        if suspended { return }

        let current = ZaloVersionProbe.read()
        let existsNow = current != nil

        switch (lastBundleExisted, existsNow, current, lastInfo) {
        case (true, false, _, _):
            lastBundleExisted = false
            lastInfo = nil
            onEvent?(.disappeared)

        case (false, true, let new?, _):
            lastBundleExisted = true
            lastInfo = new
            onEvent?(.reappeared(new))

        case (true, true, let new?, let old?):
            // Compare build number — more stable than shortVersion.
            if new.build != old.build || new.shortVersion != old.shortVersion {
                lastInfo = new
                onEvent?(.changed(new))
            }

        default:
            break
        }
    }
}
