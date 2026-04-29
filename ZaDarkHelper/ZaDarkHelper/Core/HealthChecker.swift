import Foundation

/// Snapshot of a full health-check run. Stored on AppState so the popover
/// can render results in `HealthCheckCard` and refresh on demand.
struct HealthCheckSnapshot: Equatable {
    let timestamp: Date
    let results: [HealthResult]
    var allOK: Bool { results.allSatisfy(\.ok) }
    var okCount: Int { results.filter(\.ok).count }
}

struct HealthResult: Identifiable, Equatable {
    let id: String      // stable ID per check (used as SwiftUI identity)
    let name: String    // e.g. "ZaDark CLI"
    let ok: Bool
    let detail: String  // Human-readable result line
    let icon: String    // SF Symbol name for the row
}

/// Runs read-only diagnostics in parallel. Each check is timeout-wrapped and
/// never throws — failure is encoded as `ok=false` with a friendly detail.
enum HealthChecker {

    /// Default timeout per check. Network-bound (brew tap) is the slow one;
    /// keep it tight so the whole snapshot returns < 8s.
    private static let defaultTimeout: TimeInterval = 5.0

    static func runAll(
        brew: HomebrewService,
        cli: ZaDarkCLI,
        fileManager: FileManager = .default
    ) async -> HealthCheckSnapshot {
        async let cliResult       = checkZaDarkCLI(cli: cli)
        async let asarResult      = checkZaloBundle(fileManager: fileManager)
        async let backupResult    = checkBackup(fileManager: fileManager)
        async let tapResult       = checkTap(brew: brew)
        async let tccResult       = checkAppManagement(fileManager: fileManager)
        async let codesignResult  = checkCodesign()

        let results = await [cliResult, asarResult, backupResult, tapResult, tccResult, codesignResult]
        return HealthCheckSnapshot(timestamp: .now, results: results)
    }

    // MARK: - Individual checks

    private static func checkZaDarkCLI(cli: ZaDarkCLI) async -> HealthResult {
        let id = "cli"
        let name = "ZaDark CLI"
        let icon = "terminal"
        let detail: (Bool, String) = await withTimeout(detailOnTimeout: (false, "Quá thời gian (5s)")) {
            do {
                let v = try await cli.version()
                return (true, "v\(v)")
            } catch {
                return (false, "Chưa cài — chạy 'brew install zadark'")
            }
        }
        return HealthResult(id: id, name: name, ok: detail.0, detail: detail.1, icon: icon)
    }

    private static func checkZaloBundle(fileManager: FileManager) async -> HealthResult {
        let exists = fileManager.fileExists(atPath: ZaloVersionProbe.asarPath)
        return HealthResult(
            id: "asar",
            name: "Zalo bundle",
            ok: exists,
            detail: exists ? "app.asar có tại /Applications/Zalo.app" : "app.asar không tồn tại — Zalo có thể bị hỏng",
            icon: "shippingbox"
        )
    }

    private static func checkBackup(fileManager: FileManager) async -> HealthResult {
        let exists = fileManager.fileExists(atPath: ZaloVersionProbe.asarBackupPath)
        return HealthResult(
            id: "backup",
            name: "Backup app.asar.bak",
            ok: exists,
            detail: exists ? "Backup có" : "Chưa có backup — cần áp lại ZaDark để tạo",
            icon: "externaldrive.badge.checkmark"
        )
    }

    private static func checkTap(brew: HomebrewService) async -> HealthResult {
        let id = "tap"
        let name = "Brew tap quaric/zadark"
        let icon = "spigot"
        guard brew.isInstalled() else {
            return HealthResult(id: id, name: name, ok: false, detail: "Brew chưa cài", icon: icon)
        }
        let result = await withTimeout(detailOnTimeout: (false, "Quá thời gian (5s)")) {
            do {
                let installed = try await brew.installedVersion(of: "zadark")
                if installed != nil {
                    return (true, "Đã cài (formula zadark)")
                } else {
                    return (false, "Chạy 'brew tap quaric/zadark && brew install zadark'")
                }
            } catch {
                return (false, "Lỗi truy vấn brew: \(error.localizedDescription)")
            }
        }
        return HealthResult(id: id, name: name, ok: result.0, detail: result.1, icon: icon)
    }

    /// TCC App Management probe — try opening app.asar for update. If granted,
    /// the FileHandle init succeeds. If denied, we get permission error.
    private static func checkAppManagement(fileManager: FileManager) async -> HealthResult {
        let id = "tcc"
        let name = "App Management TCC"
        let icon = "lock.shield"
        let path = ZaloVersionProbe.asarPath
        guard fileManager.fileExists(atPath: path) else {
            return HealthResult(
                id: id, name: name, ok: true,
                detail: "Bỏ qua (chưa có Zalo)",
                icon: icon
            )
        }
        do {
            let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
            try handle.close()
            return HealthResult(id: id, name: name, ok: true,
                                detail: "Đã cấp quyền", icon: icon)
        } catch {
            return HealthResult(
                id: id, name: name, ok: false,
                detail: "Bị từ chối — System Settings → Privacy → App Management",
                icon: icon
            )
        }
    }

    /// F6 — verify Zalo bundle codesign. After ZaDark patches `app.asar`,
    /// the bundle's signature breaks; helper auto-resigns adhoc but if the
    /// resign step ever fails, macOS Gatekeeper blocks launch from Finder/Dock.
    private static func checkCodesign() async -> HealthResult {
        let id = "codesign"
        let name = "Zalo codesign"
        let icon = "checkmark.seal"
        guard FileManager.default.fileExists(atPath: ZaloVersionProbe.bundlePath) else {
            return HealthResult(id: id, name: name, ok: true,
                                detail: "Bỏ qua (chưa có Zalo)", icon: icon)
        }
        let valid = await withTimeout(detailOnTimeout: false) {
            await ZaloRepairer.verifyCodesign()
        }
        return HealthResult(
            id: id, name: name, ok: valid,
            detail: valid
                ? "Hợp lệ — Finder/Dock mở được"
                : "Mismatch — chạy 'Cài lại ZaDark' để re-sign",
            icon: icon
        )
    }

    // MARK: - Timeout helper

    /// Run an async closure with a per-check deadline. Returns `detailOnTimeout`
    /// if the closure doesn't complete in time. Never throws.
    private static func withTimeout<T>(
        seconds: TimeInterval = defaultTimeout,
        detailOnTimeout: T,
        operation: @escaping @Sendable () async -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return detailOnTimeout
            }
            // First result wins.
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }
}
