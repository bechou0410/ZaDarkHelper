import AppKit
import Foundation

/// Self-update pipeline for ZaDarkHelper.
///
/// Flow:
///  1. Download the release DMG to /tmp.
///  2. Write a detached shell script that waits for the running app to quit,
///     mounts the DMG, rsync's the new .app into /Applications, ejects, strips
///     quarantine, relaunches, deletes itself.
///  3. Spawn the script via `/bin/bash` with its own process group (so it
///     survives `NSApp.terminate(nil)`).
///  4. Quit the main app. The script takes over from there.
///
/// Notes:
///  - Can't self-replace while running — macOS holds .app mach-o pages open.
///    The detached-script trick is the standard approach (used by many updaters
///    pre-Sparkle). Sparkle framework wraps this same pattern.
///  - No signature verification of downloaded DMG (app itself is unsigned dev
///    preview — once we notarize, add `spctl --assess` gate here).
enum HelperAutoUpdater {

    enum UpdateError: LocalizedError {
        case noDMGAsset
        case downloadFailed(String)
        case ioFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDMGAsset: return "Release không có file .dmg đính kèm."
            case .downloadFailed(let m): return "Tải DMG thất bại: \(m)"
            case .ioFailed(let m): return "Lỗi IO: \(m)"
            }
        }
    }

    /// Performs the full update; terminates the app on success. Never returns
    /// on the happy path (process dies). On error, throws and the app keeps running.
    static func performUpdate(
        release: GitHubReleaseChecker.Release,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let asset = release.dmgAsset else {
            throw UpdateError.noDMGAsset
        }

        // 1. Download to temp
        let tmpDMG = try await download(
            from: asset.downloadURL,
            expectedSize: asset.sizeBytes,
            progress: progress
        )

        // 2. Write updater script
        let scriptPath = try writeUpdaterScript(dmgPath: tmpDMG)

        // 3. Spawn detached
        try spawnDetached(scriptPath: scriptPath)

        // 4. Quit app on main — updater takes over
        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Steps

    private static func download(
        from url: URL,
        expectedSize: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue("ZaDarkHelper", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120

        let (tempURL, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let destPath = "/tmp/ZaDarkHelper-update.dmg"
        let destURL = URL(fileURLWithPath: destPath)
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destURL)
        } catch {
            throw UpdateError.ioFailed(error.localizedDescription)
        }

        // Rough progress tick — URLSession.download doesn't stream size naturally
        // without a delegate; post 1.0 when done so UI knows.
        progress?(1.0)

        _ = expectedSize   // reserved for future integrity check
        return destPath
    }

    private static func writeUpdaterScript(dmgPath: String) throws -> String {
        let scriptPath = "/tmp/zadark-helper-updater.sh"
        let appPath = "/Applications/ZaDarkHelper.app"
        let script = """
        #!/bin/bash
        # ZaDarkHelper self-updater — runs detached after main app quits.
        set -u

        LOG="/tmp/zadark-helper-updater.log"
        echo "[$(date)] updater start" >> "$LOG"

        # Wait for ZaDarkHelper to fully exit (max 15s).
        for i in $(seq 1 50); do
          pgrep -x ZaDarkHelper >/dev/null 2>&1 || break
          sleep 0.3
        done
        echo "[$(date)] main app gone" >> "$LOG"

        # Mount DMG
        MOUNT=$(hdiutil attach -nobrowse -noverify "\(dmgPath)" 2>>"$LOG" | awk '/\\/Volumes\\//{for(i=1;i<=NF;i++) if($i ~ /^\\/Volumes\\//) {print $i; exit}}')
        if [ -z "$MOUNT" ]; then
          echo "[$(date)] mount failed" >> "$LOG"
          exit 1
        fi
        echo "[$(date)] mounted at $MOUNT" >> "$LOG"

        # Replace app atomically-ish
        SRC="$MOUNT/ZaDarkHelper.app"
        if [ ! -d "$SRC" ]; then
          echo "[$(date)] source app not in dmg" >> "$LOG"
          hdiutil detach "$MOUNT" -quiet
          exit 2
        fi

        rm -rf "\(appPath)"
        cp -R "$SRC" "\(appPath)"
        echo "[$(date)] copied" >> "$LOG"

        # Eject + strip quarantine
        hdiutil detach "$MOUNT" -quiet
        xattr -dr com.apple.quarantine "\(appPath)" 2>/dev/null || true

        # Relaunch
        open "\(appPath)"
        echo "[$(date)] relaunched" >> "$LOG"

        # Cleanup
        rm -f "\(dmgPath)"
        rm -f "$0"
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath
        )
        return scriptPath
    }

    private static func spawnDetached(scriptPath: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptPath]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        // Let it outlive us — macOS inherits group but nohup-like effect because
        // child re-execs under its own shell session.
        try proc.run()
    }
}
