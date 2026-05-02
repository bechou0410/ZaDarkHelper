import CoreServices
import Foundation

/// FSEvents watcher on the user's Downloads folder. Scans for new files
/// matching Zalo's `gen-h-` prefix pattern and fires `onMatch` per rename
/// candidate. Owner is responsible for actually performing the rename via
/// `FilenameFixer.rename(at:)`.
final class DownloadFolderWatcher: @unchecked Sendable {

    /// Per-rename event emitted to the owner.
    struct RenameEvent: Sendable, Equatable {
        let originalURL: URL
        let newURL: URL
    }

    var onRenamed: (@Sendable (RenameEvent) -> Void)?
    var onTCCDenied: (@Sendable () -> Void)?

    let folderURL: URL
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "zadark.dl-watcher")
    private var debounceWork: DispatchWorkItem?
    private var seenInodes: Set<UInt64> = []

    init(folder: URL = DownloadFolderWatcher.defaultDownloads) {
        self.folderURL = folder
    }

    static var defaultDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Downloads").expandingTildeInPath)
    }

    func start() {
        guard stream == nil else { return }

        // Probe TCC by enumerating once. If permission denied, surface to UI
        // and skip stream creation (otherwise FSEvents silently no-ops).
        do {
            _ = try FileManager.default.contentsOfDirectory(at: folderURL,
                                                             includingPropertiesForKeys: nil)
        } catch {
            onTCCDenied?()
            return
        }

        let paths = [folderURL.path] as CFArray
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
            { _, clientInfo, _, _, _, _ in
                guard let clientInfo else { return }
                let me = Unmanaged<DownloadFolderWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                me.scheduleScan()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            // 50ms: low FSEvents coalescing latency so we react ASAP after
            // Zalo finishes writing. NoDefer flag below ensures the FIRST
            // event fires immediately without waiting for the latency window.
            0.05,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        debounceWork?.cancel()
        debounceWork = nil
    }

    /// Manual trigger — callers can invoke this for the bulk-rename action
    /// without waiting for an FSEvent.
    func scanNow() {
        queue.async { [weak self] in self?.processFolder() }
    }

    // MARK: - Private

    private func scheduleScan() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.processFolder() }
        debounceWork = work
        // 100ms debounce: groups Zalo's multi-chunk writes into one scan
        // without adding noticeable latency. Combined with FSEvents 50ms
        // coalescing → file save → rename in ~150-200ms total.
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func processFolder() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        for url in contents {
            guard FilenameFixer.target(for: url.lastPathComponent) != nil else { continue }

            // No "still writing" check: macOS `rename(2)` only swaps the
            // directory entry — the source app's open file descriptor keeps
            // writing into the same inode, so subsequent bytes land in the
            // renamed file. Safe to rename mid-write. Removing the 200ms
            // probe shaved >200ms off the rename latency (the dominant cost
            // before this change).

            do {
                if let newURL = try FilenameFixer.rename(at: url) {
                    onRenamed?(RenameEvent(originalURL: url, newURL: newURL))
                }
            } catch {
                // Conflict or other IO error — silently skip; owner can re-scan
                // later if needed.
            }
        }
    }
}
