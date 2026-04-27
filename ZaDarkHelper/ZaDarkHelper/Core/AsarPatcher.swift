import CryptoKit
import Foundation

/// Patches Electron `app.asar` archives in-place. Used to inject helper hooks
/// into Zalo's `bootstrap.js` after `zadark install` runs.
///
/// Asar format (v0):
/// ```
/// [u32 LE = 4]              — pickle alignment marker
/// [u32 LE pickleSize]       — total pickle payload from this point
/// [u32 LE stringFieldSize]  — = pickleSize - 4
/// [u32 LE jsonSize]         — actual JSON byte length
/// [bytes jsonSize]          — JSON file tree
/// [padding to 4-byte align after json]
/// [file blobs concatenated] — addressed by JSON offset/size
/// ```
///
/// We avoid full extract+repack (50MB) by doing an in-place patch:
///  1. Parse header + JSON tree
///  2. Find target file (bootstrap.js — first entry, offset 0)
///  3. Read its bytes, modify
///  4. Walk JSON tree, shift `offset` of every subsequent file by delta
///  5. Re-serialize JSON, recompute pickle sizes
///  6. Atomic write: [new header][new bootstrap.js][unchanged tail of old file]
///
/// Limitations:
///  - Only supports modifying the FIRST file (offset == 0) — true for
///    bootstrap.js in Zalo's asar layout.
///  - Doesn't support symlinks or unpacked files (we don't touch them).
///  - Recomputes integrity SHA256 + blocks for the modified file only.
enum AsarPatcher {

    enum AsarError: Error, LocalizedError {
        case invalidHeader(String)
        case fileNotFound(String)
        case unsupportedLayout(String)
        case ioFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidHeader(let m): return "Asar header lỗi: \(m)"
            case .fileNotFound(let m): return "Không tìm thấy: \(m)"
            case .unsupportedLayout(let m): return "Layout asar không hỗ trợ: \(m)"
            case .ioFailed(let m): return "IO lỗi: \(m)"
            }
        }
    }

    /// In-place modify `targetFile` (path inside the asar, e.g. `"bootstrap.js"`)
    /// using `transform`. The closure receives current content and returns new.
    /// Throws if the target isn't found or isn't the first file (offset 0).
    ///
    /// Returns: (oldSize, newSize) of target file.
    @discardableResult
    static func patchFirstFile(
        asarPath: String,
        targetFile: String,
        transform: (Data) -> Data
    ) throws -> (oldSize: Int, newSize: Int) {

        let url = URL(fileURLWithPath: asarPath)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw AsarError.ioFailed("Không mở được \(asarPath)")
        }
        defer { try? handle.close() }

        // 1. Read header (16 bytes)
        let headerData = try read(handle, 16)
        let h0 = headerData.uint32LE(at: 0)
        let pickleSize = headerData.uint32LE(at: 4)
        let stringFieldSize = headerData.uint32LE(at: 8)
        let jsonSize = headerData.uint32LE(at: 12)
        guard h0 == 4 else {
            throw AsarError.invalidHeader("magic \(h0), expected 4")
        }
        guard stringFieldSize == pickleSize - 4 else {
            throw AsarError.invalidHeader("stringFieldSize mismatch")
        }

        // 2. Read JSON
        let jsonBytes = try read(handle, Int(jsonSize))
        guard var json = try JSONSerialization.jsonObject(with: jsonBytes) as? [String: Any] else {
            throw AsarError.invalidHeader("JSON parse failed")
        }
        let dataOffset = 8 + Int(pickleSize)   // start of file blob section

        // 3. Locate target — must be first file (offset 0)
        guard var filesRoot = json["files"] as? [String: Any],
              var entry = filesRoot[targetFile] as? [String: Any],
              let offsetStr = entry["offset"] as? String,
              offsetStr == "0",
              let oldSize = entry["size"] as? Int else {
            throw AsarError.unsupportedLayout("\(targetFile) phải là file đầu tiên (offset 0)")
        }

        // 4. Read target content
        try handle.seek(toOffset: UInt64(dataOffset))
        let oldContent = try read(handle, oldSize)

        // 5. Transform
        let newContent = transform(oldContent)
        let newSize = newContent.count
        let delta = newSize - oldSize

        // 6. Update JSON: target's size + integrity, then shift all subsequent offsets
        entry["size"] = newSize
        entry["integrity"] = computeIntegrity(for: newContent)
        filesRoot[targetFile] = entry
        json["files"] = filesRoot
        // Walk tree, shift offsets > 0 by delta. Offsets are stored as decimal strings.
        shiftOffsets(in: &json, byteDelta: delta)

        // 7. Re-serialize JSON. Use compact form (no whitespace) — matches Electron's
        //    asar tool output and minimizes header bloat.
        let newJSONBytes = try JSONSerialization.data(
            withJSONObject: json,
            options: [.withoutEscapingSlashes, .sortedKeys]
        )

        // 8. Recompute pickle sizes
        let newJSONSize = newJSONBytes.count
        // string field = 4 (jsonSize header) + jsonBytes + padding to 4-byte align
        let unpaddedStrField = 4 + newJSONSize
        let pad = (4 - (unpaddedStrField % 4)) % 4
        let newStringFieldSize = unpaddedStrField + pad
        let newPickleSize = newStringFieldSize + 4

        // 9. Build new header bytes (16 bytes)
        var newHeader = Data(capacity: 16 + newStringFieldSize)
        newHeader.appendUInt32LE(4)
        newHeader.appendUInt32LE(UInt32(newPickleSize))
        newHeader.appendUInt32LE(UInt32(newStringFieldSize))
        newHeader.appendUInt32LE(UInt32(newJSONSize))
        newHeader.append(newJSONBytes)
        if pad > 0 { newHeader.append(Data(repeating: 0, count: pad)) }

        // 10. Read tail (everything after old target file in old asar)
        let oldTailStart = UInt64(dataOffset + oldSize)
        try handle.seek(toOffset: oldTailStart)
        let tail = handle.readDataToEndOfFile()

        // 11. Atomic write to a sibling temp file, then move
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).zadark-tmp")
        try? FileManager.default.removeItem(at: tmpURL)
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        guard let writeHandle = try? FileHandle(forWritingTo: tmpURL) else {
            throw AsarError.ioFailed("Không tạo được tmp file")
        }
        defer { try? writeHandle.close() }
        try writeHandle.write(contentsOf: newHeader)
        try writeHandle.write(contentsOf: newContent)
        try writeHandle.write(contentsOf: tail)
        try writeHandle.close()

        // Replace original
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)

        return (oldSize, newSize)
    }

    /// Read exactly `n` bytes or throw.
    private static func read(_ handle: FileHandle, _ n: Int) throws -> Data {
        let d = handle.readData(ofLength: n)
        guard d.count == n else {
            throw AsarError.ioFailed("Read \(d.count)/\(n) bytes")
        }
        return d
    }

    /// Walk JSON tree, add `delta` to every file's `offset` (string). Skips
    /// directory nodes (no offset) and unpacked files (offset doesn't matter
    /// since content lives elsewhere).
    private static func shiftOffsets(in json: inout [String: Any], byteDelta: Int) {
        if byteDelta == 0 { return }
        guard var files = json["files"] as? [String: Any] else { return }
        files = walkAndShift(files, delta: byteDelta)
        json["files"] = files
    }

    private static func walkAndShift(_ node: [String: Any], delta: Int) -> [String: Any] {
        var result = node
        for (key, value) in node {
            guard var entry = value as? [String: Any] else { continue }
            if let children = entry["files"] as? [String: Any] {
                entry["files"] = walkAndShift(children, delta: delta)
            } else if let offsetStr = entry["offset"] as? String,
                      let offset = Int(offsetStr) {
                if offset > 0 {
                    entry["offset"] = String(offset + delta)
                }
                // offset == 0 → the file we just modified, already updated separately
            }
            result[key] = entry
        }
        return result
    }

    /// Compute integrity dict matching Electron asar tool output format.
    private static func computeIntegrity(for content: Data) -> [String: Any] {
        let blockSize = 4 * 1024 * 1024   // 4 MB blocks (asar default)
        let fullHash = SHA256.hash(data: content)
        let fullHashHex = fullHash.map { String(format: "%02x", $0) }.joined()

        var blocks: [String] = []
        if content.isEmpty {
            blocks = [fullHashHex]
        } else {
            var i = 0
            while i < content.count {
                let end = min(i + blockSize, content.count)
                let chunk = content[i..<end]
                let h = SHA256.hash(data: chunk)
                blocks.append(h.map { String(format: "%02x", $0) }.joined())
                i = end
            }
        }
        return [
            "algorithm": "SHA256",
            "hash": fullHashHex,
            "blockSize": blockSize,
            "blocks": blocks
        ]
    }
}

// MARK: - Data helpers

private extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    mutating func appendUInt32LE(_ v: UInt32) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
        append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 24) & 0xff))
    }
}
