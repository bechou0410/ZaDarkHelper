import AppKit
import CryptoKit
import Foundation

/// Reads Zalo app metadata without modifying anything.
/// Pure functions — no shared state, safe to call from any actor.
struct ZaloInfo: Equatable, Sendable {
    let shortVersion: String
    let build: String
    let bundleIdentifier: String
    let asarSHA256: String?
}

enum ZaloVersionProbe {
    static let bundlePath = "/Applications/Zalo.app"
    static let infoPlistPath = "/Applications/Zalo.app/Contents/Info.plist"
    static let asarPath = "/Applications/Zalo.app/Contents/Resources/app.asar"
    static let asarBackupPath = "/Applications/Zalo.app/Contents/Resources/app.asar.bak"
    static let bundleIDFallback = "com.vng.zalo"

    /// Returns parsed Zalo metadata, or nil if bundle is missing / unreadable.
    static func read(computeHash: Bool = false, fileManager: FileManager = .default) -> ZaloInfo? {
        guard fileManager.fileExists(atPath: infoPlistPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let shortVersion = (plist["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (plist["CFBundleVersion"] as? String) ?? "?"
        let bundleID = (plist["CFBundleIdentifier"] as? String) ?? bundleIDFallback

        let hash: String? = computeHash ? sha256OfAsar() : nil

        return ZaloInfo(
            shortVersion: shortVersion,
            build: build,
            bundleIdentifier: bundleID,
            asarSHA256: hash
        )
    }

    /// True if Zalo process is currently running.
    static func isRunning() -> Bool {
        !runningInstances().isEmpty
    }

    static func runningInstances() -> [NSRunningApplication] {
        let info = read()
        let id = info?.bundleIdentifier ?? bundleIDFallback
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
    }

    /// Whether a ZaDark backup exists at the expected path.
    /// Presence is a strong signal that the current app.asar has been patched.
    static func hasBackup(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: asarBackupPath)
    }

    /// SHA256 of app.asar, streamed in 64KB chunks. Returns nil on IO error.
    static func sha256OfAsar() -> String? {
        let url = URL(fileURLWithPath: asarPath)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 65536)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
