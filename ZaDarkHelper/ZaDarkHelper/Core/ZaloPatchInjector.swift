import CryptoKit
import Foundation

/// Injects a small Electron `will-download` hook into Zalo's `bootstrap.js`
/// inside `app.asar`. The hook strips `gen-{tag}-` cache prefix from save
/// dialog default filename — fixing the bug at source instead of renaming
/// after save (which is what `FilenameFixer` does as a fallback).
///
/// Idempotent: detects the marker and skips re-injection.
/// Reversible: `removePatch(asarPath:)` strips the appended block.
enum ZaloPatchInjector {

    /// Marker comment so we can detect/replace/remove our injection.
    /// Must be unique enough that no future Zalo bootstrap.js will collide.
    static let marker = "// ZADARK_HELPER_FILENAME_FIX_v1 — do not edit"
    static let endMarker = "// ZADARK_HELPER_FILENAME_FIX_END"

    /// The actual JS appended to bootstrap.js. Wrapped in IIFE so it doesn't
    /// pollute bootstrap scope. Soft-fails on any error so a future Electron
    /// API change can never break Zalo startup.
    static let hookSource = """

    \(marker)
    ;(() => {
      try {
        const { session } = require('electron')
        const RX = /^gen-[a-z0-9]{1,4}-/i
        session.fromPartition('persist:zalo').on('will-download', (event, item) => {
          try {
            const original = item.getFilename()
            const fixed = original.replace(RX, '')
            if (fixed !== original) {
              item.setSaveDialogOptions({ defaultPath: fixed })
            }
          } catch (_) { /* ignore — never block Zalo save */ }
        })
      } catch (_) { /* ignore — never break Zalo startup */ }
    })()
    \(endMarker)

    """

    enum InjectError: Error, LocalizedError {
        case asarMissing(String)
        case alreadyPatched
        case patchFailed(String)

        var errorDescription: String? {
            switch self {
            case .asarMissing(let p): return "Không thấy app.asar tại \(p)"
            case .alreadyPatched: return "Đã patch trước đó."
            case .patchFailed(let m): return "Patch app.asar lỗi: \(m)"
            }
        }
    }

    /// True if `bootstrap.js` inside the asar already contains our marker.
    /// Cheap check: read just the bootstrap.js bytes and search for marker.
    static func isPatched(asarPath: String = ZaloVersionProbe.asarPath) -> Bool {
        do {
            let content = try readBootstrapJS(asarPath: asarPath)
            return content.contains(marker)
        } catch {
            return false
        }
    }

    /// Apply the patch. Returns true if newly applied, false if already patched.
    @discardableResult
    static func applyPatch(asarPath: String = ZaloVersionProbe.asarPath) throws -> Bool {
        guard FileManager.default.fileExists(atPath: asarPath) else {
            throw InjectError.asarMissing(asarPath)
        }

        // Quick idempotency check before any heavy work.
        if isPatched(asarPath: asarPath) {
            return false
        }

        do {
            try AsarPatcher.patchFirstFile(
                asarPath: asarPath,
                targetFile: "bootstrap.js"
            ) { oldContent in
                guard var text = String(data: oldContent, encoding: .utf8) else {
                    return oldContent
                }
                // Defensive: if old marker leaked through (should be caught by
                // isPatched), strip first to avoid duplicate.
                text = stripExistingHook(from: text)
                text += hookSource
                return text.data(using: .utf8) ?? oldContent
            }
            return true
        } catch {
            throw InjectError.patchFailed("\(error)")
        }
    }

    /// Remove the patch (called when user toggles feature off). Best-effort —
    /// if asar layout changed, returns false but doesn't throw.
    @discardableResult
    static func removePatch(asarPath: String = ZaloVersionProbe.asarPath) throws -> Bool {
        guard FileManager.default.fileExists(atPath: asarPath) else { return false }
        if !isPatched(asarPath: asarPath) { return false }

        do {
            try AsarPatcher.patchFirstFile(
                asarPath: asarPath,
                targetFile: "bootstrap.js"
            ) { oldContent in
                guard let text = String(data: oldContent, encoding: .utf8) else {
                    return oldContent
                }
                let stripped = stripExistingHook(from: text)
                return stripped.data(using: .utf8) ?? oldContent
            }
            return true
        } catch {
            throw InjectError.patchFailed("\(error)")
        }
    }

    // MARK: - Private

    /// Read just the first file (bootstrap.js) from the asar. Avoids
    /// extracting the whole archive when we only need a marker check.
    private static func readBootstrapJS(asarPath: String) throws -> String {
        let url = URL(fileURLWithPath: asarPath)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw InjectError.asarMissing(asarPath)
        }
        defer { try? handle.close() }

        // Header: 16 bytes pickle prefix
        let header = handle.readData(ofLength: 16)
        guard header.count == 16 else {
            throw InjectError.patchFailed("Asar header too short")
        }
        let pickleSize = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }.littleEndian
        let jsonSize = header.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }.littleEndian

        let jsonBytes = handle.readData(ofLength: Int(jsonSize))
        guard let json = try? JSONSerialization.jsonObject(with: jsonBytes) as? [String: Any],
              let files = json["files"] as? [String: Any],
              let bootstrap = files["bootstrap.js"] as? [String: Any],
              let size = bootstrap["size"] as? Int,
              let offsetStr = bootstrap["offset"] as? String,
              let offset = Int(offsetStr) else {
            throw InjectError.patchFailed("Asar JSON shape unexpected")
        }

        let dataOffset = 8 + Int(pickleSize)
        try handle.seek(toOffset: UInt64(dataOffset + offset))
        let content = handle.readData(ofLength: size)
        return String(data: content, encoding: .utf8) ?? ""
    }

    /// Strip the marker..endMarker block (and the leading newline/IIFE) from
    /// bootstrap text. Safe even if either marker missing — returns input.
    private static func stripExistingHook(from text: String) -> String {
        guard let start = text.range(of: marker),
              let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex) else {
            return text
        }
        // Walk back from `start` to consume any leading newline so we don't
        // leave a blank line in bootstrap.js.
        var trimStart = start.lowerBound
        if trimStart > text.startIndex,
           text[text.index(before: trimStart)] == "\n" {
            trimStart = text.index(before: trimStart)
        }
        return String(text[..<trimStart] + text[end.upperBound...])
    }
}
