import Foundation

/// Auto-recover logic for the failure mode encountered in v26.4.006:
///
/// When Zalo's Squirrel auto-updater downloads a new Zalo version, helper's
/// auto re-patch flow ran `zadark install` while a stale `app.asar.bak`
/// (from before the Squirrel update) was still present. ZaDark CLI's
/// install flow reverts `.asar` from `.bak` first → end result is OLD Zalo
/// content with NEW Zalo's bundle code signature → macOS Gatekeeper marks
/// the app "damaged" and refuses to launch from Finder/Dock.
///
/// Fix has two parts, both run by `ReinstallOrchestrator` around `cli.install`:
///
/// 1. **Before**: if Zalo build version differs from `lastPatchedZaloBuild`,
///    `.bak` is stale → delete it. ZaDark CLI then patches the current
///    NEW Zalo asar instead of rolling back to the obsolete backup.
///
/// 2. **After**: codesign --force --deep --sign - --options=runtime so the
///    bundle's signature is self-consistent (adhoc + hardened-runtime flag,
///    which launchd requires). Without this step launchd refuses to spawn
///    Zalo even when codesign verifies as valid.
enum ZaloRepairer {

    enum RepairError: Error, LocalizedError {
        case codesignFailed(stderr: String, exit: Int32)

        var errorDescription: String? {
            switch self {
            case .codesignFailed(let stderr, let exit):
                return "Ký lại Zalo thất bại (exit \(exit)): \(stderr)"
            }
        }
    }

    /// Stale = `.bak` exists but the last patched Zalo build (recorded by
    /// helper) differs from the current bundle build. Indicates Squirrel
    /// auto-update happened between two helper sessions.
    ///
    /// Returns true if `.bak` was removed.
    @discardableResult
    static func removeStaleBackupIfNeeded(
        currentBuild: String,
        lastPatchedBuild: String?,
        fileManager: FileManager = .default
    ) -> Bool {
        let bakPath = ZaloVersionProbe.asarBackupPath
        guard fileManager.fileExists(atPath: bakPath) else { return false }

        // First-time install (no recorded prior patch) — keep .bak as fresh
        // (it's whatever ZaDark just made; not stale).
        guard let last = lastPatchedBuild else { return false }

        // Builds match → patches are still valid for current Zalo.
        if last == currentBuild { return false }

        // Mismatch → Zalo updated since we last patched. .bak is from old
        // version → ZaDark's rollback would corrupt the current bundle.
        try? fileManager.removeItem(atPath: bakPath)
        return true
    }

    /// Re-sign Zalo.app with adhoc identity + hardened runtime flag.
    ///
    /// `codesign --force --deep --sign - --options=runtime`
    ///
    /// - `--force`: overwrite existing signature
    /// - `--deep`: include nested helper apps (Renderer/GPU/Plugin)
    /// - `--sign -`: adhoc (no developer cert needed)
    /// - `--options=runtime`: preserve hardened-runtime flag from VNG's
    ///   original codesign — without this, launchd refuses to spawn the
    ///   adhoc-signed bundle (RBSRequestErrorDomain "Launch failed").
    static func adhocResign(
        shell: ShellRunning = ShellRunner(),
        onLine: (@Sendable (ShellLine) -> Void)? = nil
    ) async throws {
        let result = try await shell.run(
            "/usr/bin/codesign",
            args: [
                "--force", "--deep",
                "--sign", "-",
                "--options=runtime",
                ZaloVersionProbe.bundlePath
            ],
            env: nil,
            onLine: onLine
        )
        guard result.ok else {
            throw RepairError.codesignFailed(stderr: result.stderr, exit: result.exitCode)
        }
    }

    /// Lightweight verify — used by HealthChecker. Returns true if codesign
    /// reports valid. Caller doesn't care about adhoc vs VNG, just whether
    /// macOS will allow launch.
    static func verifyCodesign(
        shell: ShellRunning = ShellRunner()
    ) async -> Bool {
        let result = try? await shell.run(
            "/usr/bin/codesign",
            args: ["--verify", ZaloVersionProbe.bundlePath],
            env: nil,
            onLine: nil
        )
        return result?.ok == true
    }
}
