import Foundation

/// Pure logic for stripping Zalo's `gen-h-` cache prefix from saved filenames.
///
/// When ZaDark patches Zalo's popup-viewer, saving an image from the preview
/// uses Zalo's internal cache filename which has the form
/// `gen-h-{originalId}.{ext}`. The 'gen-h-' is Zalo's cache convention,
/// not a ZaDark feature. This struct undoes the prefix on the helper side.
enum FilenameFixer {

    enum FixerError: Error, LocalizedError {
        case conflict(existing: URL)

        var errorDescription: String? {
            switch self {
            case .conflict(let url):
                return "Đã tồn tại tệp \(url.lastPathComponent) — không ghi đè."
            }
        }
    }

    /// Whitelist of media extensions Zalo saves. Keep tight to avoid false
    /// positives on rare files that happen to start with `gen-h-`.
    static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif",
        "mp4", "mov", "m4v"
    ]

    /// Returns the target filename (without prefix) if input matches the
    /// pattern, else nil.
    static func target(for filename: String) -> String? {
        let lower = filename.lowercased()
        guard lower.hasPrefix("gen-h-") else { return nil }
        let stripped = String(filename.dropFirst("gen-h-".count))

        // Must have a recognized extension to qualify.
        let ext = (stripped as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, allowedExtensions.contains(ext) else { return nil }

        // Must have non-empty base name after prefix strip.
        let base = (stripped as NSString).deletingPathExtension
        guard !base.isEmpty else { return nil }

        return stripped
    }

    /// Atomically rename file at URL — strip prefix.
    /// Returns the new URL on success, nil if input doesn't need fixing.
    /// Throws `FixerError.conflict` if destination already exists.
    @discardableResult
    static func rename(at url: URL, fileManager: FileManager = .default) throws -> URL? {
        guard let targetName = target(for: url.lastPathComponent) else { return nil }
        let dest = url.deletingLastPathComponent().appendingPathComponent(targetName)

        if fileManager.fileExists(atPath: dest.path) {
            throw FixerError.conflict(existing: dest)
        }
        try fileManager.moveItem(at: url, to: dest)
        return dest
    }

    /// Reverse a previous rename — for the toast undo action.
    /// Moves `currentURL` back to its original `gen-h-` name.
    static func undoRename(currentURL: URL, originalName: String,
                           fileManager: FileManager = .default) throws {
        let original = currentURL.deletingLastPathComponent()
            .appendingPathComponent(originalName)
        if fileManager.fileExists(atPath: original.path) {
            throw FixerError.conflict(existing: original)
        }
        try fileManager.moveItem(at: currentURL, to: original)
    }

    /// Bulk-rename: scan a folder, rename every file matching pattern.
    /// Returns count of renamed files + list of errors.
    static func scanAndRename(in folder: URL,
                              fileManager: FileManager = .default
    ) -> (renamed: Int, errors: [Error]) {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            return (0, [error])
        }

        var renamed = 0
        var errors: [Error] = []
        for url in contents {
            do {
                if try rename(at: url, fileManager: fileManager) != nil {
                    renamed += 1
                }
            } catch {
                errors.append(error)
            }
        }
        return (renamed, errors)
    }
}
