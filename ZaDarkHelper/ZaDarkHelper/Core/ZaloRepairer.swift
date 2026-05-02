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

    /// Always remove `.bak` before any helper-driven `zadark install`, except
    /// on the very first install (where helper hasn't yet taken ownership).
    ///
    /// Why unconditional after first install:
    ///   ZaDark CLI's install flow ALWAYS does a rollback when both `.asar`
    ///   and `.bak` exist: `.bak` → `.asar`, then patches → repacks. If `.bak`
    ///   captured pre-Squirrel-update Zalo content, the rollback overwrites
    ///   the new Squirrel-updated `.asar` with stale content. Result: bundle
    ///   has OLD Zalo asar + NEW Electron Frameworks → crash on launch
    ///   (`Library not loaded` / Team ID mismatch).
    ///
    ///   The `lastPatchedBuild == currentBuild` shortcut from v26.4.007 was
    ///   wrong — helper updates lastPatchedBuild after every install regardless
    ///   of whether the content actually got refreshed, so the comparison can
    ///   trivially match while `.bak` is silently stale.
    ///
    /// Trade-off: removing `.bak` means `zadark uninstall` can no longer
    /// restore the original Zalo. That's acceptable here — user's recovery
    /// path for an unwanted ZaDark is now "reinstall Zalo from VNG", which
    /// is what they'd need to do anyway after a stale-`.bak` corruption.
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

        // First-time install — keep .bak so ZaDark uninstall has a valid
        // restore point at least once. Subsequent installs delete it.
        guard lastPatchedBuild != nil else { return false }

        try? fileManager.removeItem(atPath: bakPath)
        return true
    }

    /// Re-sign Zalo.app with adhoc identity + hardened runtime + Electron
    /// entitlements injected from a bundled plist.
    ///
    /// `codesign --force --deep --sign - --options=runtime --entitlements <plist>`
    ///
    /// - `--force`: overwrite existing signature
    /// - `--deep`: include nested helper apps (Renderer/GPU/Plugin) + Frameworks
    /// - `--sign -`: adhoc (no developer cert needed)
    /// - `--options=runtime`: preserve hardened-runtime flag
    /// - `--entitlements`: critical — without explicit entitlements the
    ///   adhoc resign STRIPS VNG's original entitlements. Hardened-runtime +
    ///   library-validation enforcement then crashes Electron with
    ///   "Library not loaded ... different Team IDs". Bundled
    ///   `zalo-entitlements.plist` includes `disable-library-validation` +
    ///   JIT permissions so the patched bundle launches cleanly.
    static func adhocResign(
        shell: ShellRunning = ShellRunner(),
        onLine: (@Sendable (ShellLine) -> Void)? = nil
    ) async throws {
        let entitlementsPath = try writeBundledEntitlements()

        let result = try await shell.run(
            "/usr/bin/codesign",
            args: [
                "--force", "--deep",
                "--sign", "-",
                "--options=runtime",
                "--entitlements", entitlementsPath,
                ZaloVersionProbe.bundlePath
            ],
            env: nil,
            onLine: onLine
        )
        guard result.ok else {
            throw RepairError.codesignFailed(stderr: result.stderr, exit: result.exitCode)
        }
    }

    /// Copy the bundled `zalo-entitlements.plist` to a stable temp path so
    /// codesign can read it. Returns the path for use as `--entitlements` arg.
    private static func writeBundledEntitlements() throws -> String {
        guard let bundleURL = Bundle.main.url(forResource: "zalo-entitlements",
                                              withExtension: "plist") else {
            throw RepairError.codesignFailed(
                stderr: "Bundled zalo-entitlements.plist not found in helper",
                exit: -1
            )
        }
        let dest = "/tmp/zadark-helper-zalo-entitlements.plist"
        try? FileManager.default.removeItem(atPath: dest)
        try FileManager.default.copyItem(at: bundleURL,
                                         to: URL(fileURLWithPath: dest))
        return dest
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
