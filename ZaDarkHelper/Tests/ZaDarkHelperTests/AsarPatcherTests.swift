import CryptoKit
import XCTest
@testable import ZaDarkHelper

/// F4 — sanity-check that AsarPatcher's in-place modification correctly
/// updates pickle headers, JSON offsets, and file integrity. We synthesize
/// a small fake asar in memory to avoid depending on a real Zalo install.
final class AsarPatcherTests: XCTestCase {

    /// Minimal asar with 2 files: bootstrap.js (offset 0) + foo.txt.
    /// Returns the path on disk so AsarPatcher can read+write it.
    private func makeFakeAsar(
        bootstrap: String,
        foo: String
    ) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let asarURL = dir.appendingPathComponent("test.asar")

        let bootstrapData = bootstrap.data(using: .utf8)!
        let fooData = foo.data(using: .utf8)!

        let json: [String: Any] = [
            "files": [
                "bootstrap.js": [
                    "size": bootstrapData.count,
                    "offset": "0",
                    "integrity": integrity(of: bootstrapData)
                ],
                "foo.txt": [
                    "size": fooData.count,
                    "offset": "\(bootstrapData.count)",
                    "integrity": integrity(of: fooData)
                ]
            ]
        ]
        let jsonBytes = try JSONSerialization.data(
            withJSONObject: json,
            options: [.withoutEscapingSlashes, .sortedKeys]
        )

        // Build pickle: jsonSize + json + pad
        let jsonSize = jsonBytes.count
        let unpaddedStrField = 4 + jsonSize
        let pad = (4 - (unpaddedStrField % 4)) % 4
        let stringFieldSize = unpaddedStrField + pad
        let pickleSize = stringFieldSize + 4

        var data = Data(capacity: 16 + stringFieldSize + bootstrapData.count + fooData.count)
        data.appendUInt32LE(4)
        data.appendUInt32LE(UInt32(pickleSize))
        data.appendUInt32LE(UInt32(stringFieldSize))
        data.appendUInt32LE(UInt32(jsonSize))
        data.append(jsonBytes)
        if pad > 0 { data.append(Data(repeating: 0, count: pad)) }
        data.append(bootstrapData)
        data.append(fooData)
        try data.write(to: asarURL)
        return asarURL
    }

    private func integrity(of data: Data) -> [String: Any] {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return [
            "algorithm": "SHA256",
            "hash": hash,
            "blockSize": 4 * 1024 * 1024,
            "blocks": [hash]
        ]
    }

    // MARK: - Tests

    func test_patchFirstFile_appendsAndShiftsOffset() throws {
        let asar = try makeFakeAsar(
            bootstrap: "console.log('hi');",
            foo: "second file content"
        )
        defer { try? FileManager.default.removeItem(at: asar.deletingLastPathComponent()) }

        let result = try AsarPatcher.patchFirstFile(
            asarPath: asar.path,
            targetFile: "bootstrap.js"
        ) { old in
            var s = String(data: old, encoding: .utf8) ?? ""
            s += "\n// extra"
            return s.data(using: .utf8)!
        }

        XCTAssertEqual(result.oldSize, "console.log('hi');".utf8.count)
        XCTAssertGreaterThan(result.newSize, result.oldSize)

        // Re-read and verify foo.txt is still intact at its new offset
        let raw = try Data(contentsOf: asar)
        let pickleSize = raw.uint32LE(at: 4)
        let jsonSize = raw.uint32LE(at: 12)
        let json = try JSONSerialization.jsonObject(with: raw[16..<16 + Int(jsonSize)]) as! [String: Any]
        let files = json["files"] as! [String: Any]
        let foo = files["foo.txt"] as! [String: Any]
        let fooOffset = Int(foo["offset"] as! String)!
        let fooSize = foo["size"] as! Int
        let dataStart = 8 + Int(pickleSize)
        let fooBytes = raw[dataStart + fooOffset..<dataStart + fooOffset + fooSize]
        XCTAssertEqual(String(data: fooBytes, encoding: .utf8), "second file content")
    }

    func test_patchFirstFile_idempotentRoundtrip() throws {
        // Apply same transform twice — second run should still produce valid asar
        // with foo.txt intact.
        let asar = try makeFakeAsar(
            bootstrap: "BOOT",
            foo: "FOO"
        )
        defer { try? FileManager.default.removeItem(at: asar.deletingLastPathComponent()) }

        for _ in 0..<2 {
            try AsarPatcher.patchFirstFile(
                asarPath: asar.path,
                targetFile: "bootstrap.js"
            ) { _ in
                "BOOT_PATCHED".data(using: .utf8)!
            }
        }

        // foo.txt should still equal "FOO"
        let raw = try Data(contentsOf: asar)
        let pickleSize = raw.uint32LE(at: 4)
        let jsonSize = raw.uint32LE(at: 12)
        let json = try JSONSerialization.jsonObject(with: raw[16..<16 + Int(jsonSize)]) as! [String: Any]
        let files = json["files"] as! [String: Any]
        let foo = files["foo.txt"] as! [String: Any]
        let fooOffset = Int(foo["offset"] as! String)!
        let fooSize = foo["size"] as! Int
        let dataStart = 8 + Int(pickleSize)
        let fooBytes = raw[dataStart + fooOffset..<dataStart + fooOffset + fooSize]
        XCTAssertEqual(String(data: fooBytes, encoding: .utf8), "FOO")
    }

    // MARK: - ZaloPatchInjector

    func test_injector_appliesAndRemovesIdempotently() throws {
        let asar = try makeFakeAsar(
            bootstrap: "// bootstrap\nrequire('./main');\n",
            foo: "F"
        )
        defer { try? FileManager.default.removeItem(at: asar.deletingLastPathComponent()) }

        XCTAssertFalse(ZaloPatchInjector.isPatched(asarPath: asar.path))

        let firstApply = try ZaloPatchInjector.applyPatch(asarPath: asar.path)
        XCTAssertTrue(firstApply)
        XCTAssertTrue(ZaloPatchInjector.isPatched(asarPath: asar.path))

        // Apply twice → second run is no-op
        let secondApply = try ZaloPatchInjector.applyPatch(asarPath: asar.path)
        XCTAssertFalse(secondApply)

        // Remove → marker gone
        let removed = try ZaloPatchInjector.removePatch(asarPath: asar.path)
        XCTAssertTrue(removed)
        XCTAssertFalse(ZaloPatchInjector.isPatched(asarPath: asar.path))

        // Idempotent remove
        let secondRemove = try ZaloPatchInjector.removePatch(asarPath: asar.path)
        XCTAssertFalse(secondRemove)
    }
}

// MARK: - Test helpers

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
