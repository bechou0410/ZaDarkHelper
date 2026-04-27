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
            0.5,
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
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func processFolder() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        for url in contents {
            guard FilenameFixer.target(for: url.lastPathComponent) != nil else { continue }
            // Skip if file is still being written (size changing within 200ms).
            if isFileStillWriting(url: url) { continue }

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

    /// Heuristic: if the file's size changed within a 200ms window, treat as
    /// still being written. Avoids racing the source app mid-write.
    private func isFileStillWriting(url: URL) -> Bool {
        guard let attrs1 = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size1 = attrs1[.size] as? Int else { return false }
        Thread.sleep(forTimeInterval: 0.2)
        guard let attrs2 = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size2 = attrs2[.size] as? Int else { return false }
        return size1 != size2
    }
}
