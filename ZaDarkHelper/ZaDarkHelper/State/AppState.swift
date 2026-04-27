import AppKit
import Foundation
import Observation

/// Central observable state for the menu-bar UI.
/// Owns the long-running services (watcher, observer, scheduler) and the orchestrator.
@MainActor
@Observable
final class AppState {

    // MARK: - Public status model

    enum Status: Equatable {
        case initializing
        case brewMissing
        case notInstalled
        case installed(version: String)
        case updateAvailable(current: String, latest: String?)
        case stale(zaloVersion: String, lastPatchedBuild: String?)
        case broken    // app.asar missing, backup exists — Zalo can't launch
        case working(String)
        case error(String)
    }

    // MARK: - Observable state

    var status: Status = .initializing
    var zaloInfo: ZaloInfo?
    var installedZaDarkVersion: String?
    var hasBrew: Bool = false
    var hasBackup: Bool = false
    var hasAppManagementPermission: Bool = true   // assume yes until a write fails

    /// Finished sessions, oldest → newest. Trimmed to `maxSessions`.
    var sessions: [LogSession] = []
    /// Currently-open session — exists while an action is in flight.
    var currentSession: LogSession?
    /// Log filter state (per stream). Read by LogDrawerView.
    var showStdout: Bool = true
    var showStderr: Bool = true

    var preferences: Preferences = Preferences.load()
    var lastUpdateCheck: Date?
    /// Latest helper release from GitHub if newer than current. Nil when up-to-date or unchecked.
    var helperUpdate: GitHubReleaseChecker.Release?

    /// True while a manual check-for-update is in flight. Banner views
    /// observe this to suppress themselves during loading so the user sees
    /// the hero spinner alone, not a banner flashing mid-check.
    var isCheckingForUpdate: Bool = false

    /// F1 — banner shown when Downloads access is denied (TCC), so the user
    /// can grant Full Disk Access. Persists until they retry successfully.
    var downloadFolderAccessDenied: Bool = false
    /// F1 — true while a bulk-rename pass is running (used to disable button).
    var isBulkRenamingDownloads: Bool = false
    /// F1 — last bulk-rename result (count + transient toast text). nil = none yet.
    var lastBulkRenameCount: Int?

    /// F2 — last health-check snapshot. When non-nil, MainPopoverView swaps the
    /// hero slot for HealthCheckCard. User dismisses by tapping "Đóng".
    var lastHealthCheck: HealthCheckSnapshot?
    /// F2 — true while a health-check pass is running (used to disable button).
    var isRunningHealthCheck: Bool = false

    /// F4 — last asar-patch injection result. true=patched, false=not patched
    /// (either disabled or marker absent). UI uses this to render a chip.
    var asarPatchActive: Bool = false

    /// Invoked when AppState wants the UI to surface itself (popover opens).
    /// Set by `StatusBarController` at init. Fires on:
    ///   • newly detected helper update
    ///   • Zalo drift detected and user hasn't opted into auto re-patch
    var onRequestSurface: (@Sendable () -> Void)?
    var isBusy: Bool { if case .working = status { return true } else { return false } }
    var toastMessage: String?


    /// Flat view of all lines (finished + current) for diagnostics + backwards compat.
    var logLines: [LogLine] {
        var out: [LogLine] = []
        out.reserveCapacity(maxLogLines)
        for s in sessions { out.append(contentsOf: s.lines) }
        if let cur = currentSession { out.append(contentsOf: cur.lines) }
        return out
    }

    /// Sessions to show in the drawer, newest first, includes open session if any.
    var sessionsForDisplay: [LogSession] {
        var arr = sessions
        if let cur = currentSession { arr.append(cur) }
        return arr.reversed()
    }

    // MARK: - Services

    private let shell: ShellRunning
    private let brew: HomebrewService
    private let cli: ZaDarkCLI
    private let watcher: ZaloBundleWatcher
    private let workspace: WorkspaceObserver
    private let downloadWatcher = DownloadFolderWatcher()
    private let deferredUpdate = DeferredUpdateManager()
    private let orchestrator: ReinstallOrchestrator
    private let scheduler: UpdateScheduler
    private let prefsStorage: PreferencesStorage
    private let maxLogLines = 500
    private let maxSessions = 20

    // MARK: - Init

    init(
        shell: ShellRunning = ShellRunner(),
        prefsStorage: PreferencesStorage = .init()
    ) {
        self.shell = shell
        self.prefsStorage = prefsStorage
        self.lastUpdateCheck = prefsStorage.lastUpdateCheck()
        self.brew = HomebrewService(shell: shell)
        self.cli = ZaDarkCLI(shell: shell)
        self.watcher = ZaloBundleWatcher()
        self.workspace = WorkspaceObserver()
        self.hasBrew = brew.isInstalled()
        // Temporary scheduler — closure will be reassigned in startBackgroundServices.
        self.scheduler = UpdateScheduler(onTick: {})

        // Make a log sink that can be captured by the orchestrator from init.
        let weakBox = WeakBox()
        self.orchestrator = ReinstallOrchestrator(
            brew: brew,
            cli: cli,
            watcher: watcher,
            prefsStorage: prefsStorage,
            logSink: { line in
                Task { @MainActor in
                    weakBox.state?.appendLog(line)
                }
            }
        )
        weakBox.state = self
    }

    private final class WeakBox { weak var state: AppState? }

    // MARK: - Lifecycle

    private var didStart = false

    /// Idempotent — may be called from both App.init (eager, before first click)
    /// and MainPopoverView.task (safety net). Only arms watchers once.
    func start() {
        guard !didStart else { return }
        didStart = true
        startWatchers()
        probeAppManagementPermission()
        applyFilenameFixerPreference()
        NotificationService.registerCategories()
        // F3 — sweep stale DMGs left in /tmp from previous installs.
        HelperAutoUpdater.cleanupOrphanDMGs()
        // F4 — DEPRECATED. Auto-cleanup any v26.4.004 patch on launch.
        // The patch approach was fundamentally flawed (see Preferences doc);
        // we silently remove it so users upgrading from v26.4.004 get back
        // to a clean Zalo state without manual intervention.
        cleanupDeprecatedAsarPatch()
        Task {
            await refresh()
            await checkForHelperUpdate()
        }
    }

    /// Attempt O_RDWR on app.asar. Succeeds if TCC App Management is granted.
    /// Also registers this app in the App Management list in System Settings.
    func probeAppManagementPermission() {
        let path = ZaloVersionProbe.asarPath
        guard FileManager.default.fileExists(atPath: path) else {
            hasAppManagementPermission = true   // no Zalo yet, nothing to block
            return
        }
        do {
            let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
            try handle.close()
            hasAppManagementPermission = true
        } catch {
            hasAppManagementPermission = false
        }
    }

    // MARK: - Derived

    var menuBarIconName: String {
        switch status {
        case .working: return "moon.stars"
        case .installed: return "moon.stars.fill"
        case .stale, .updateAvailable: return "exclamationmark.circle.fill"
        case .broken, .error: return "xmark.octagon.fill"
        case .brewMissing, .notInstalled, .initializing: return "moon"
        }
    }

    /// True when Zalo.app is in the "backup-only" state: `app.asar.bak` exists
    /// but `app.asar` is gone — Zalo cannot launch. Happens when an install/uninstall
    /// cycle was interrupted between `deleteFile app.asar` and `renameFile app.asar.bak`.
    var isZaloBroken: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: ZaloVersionProbe.asarBackupPath)
            && !fm.fileExists(atPath: ZaloVersionProbe.asarPath)
    }

    // MARK: - Public actions

    func refresh() async {
        hasBrew = brew.isInstalled()
        guard hasBrew else {
            status = .brewMissing
            return
        }

        // Broken state takes precedence over everything else — user MUST repair before Zalo launches.
        if isZaloBroken {
            let wasAlreadyBroken: Bool
            if case .broken = status { wasAlreadyBroken = true } else { wasAlreadyBroken = false }
            status = .broken
            hasBackup = true
            zaloInfo = ZaloVersionProbe.read()
            installedZaDarkVersion = try? await brew.installedVersion(of: "zadark")
            // Newly broken → surface popover so user sees the Repair button immediately.
            if !wasAlreadyBroken { onRequestSurface?() }
            return
        }

        do {
            let installed = try await brew.installedVersion(of: "zadark")
            installedZaDarkVersion = installed
            zaloInfo = ZaloVersionProbe.read()
            hasBackup = ZaloVersionProbe.hasBackup()

            guard let installed else {
                status = .notInstalled
                return
            }

            // Compare patch marker against current Zalo build
            if let zalo = zaloInfo {
                let lastBuild = prefsStorage.lastPatchedZaloBuild()
                if lastBuild != zalo.build || !ZaloVersionProbe.hasBackup() {
                    status = .stale(zaloVersion: zalo.shortVersion, lastPatchedBuild: lastBuild)
                    return
                }
            }

            // Check if formula is outdated (non-fatal)
            let outdated = (try? await brew.outdated("zadark")) ?? false
            if outdated {
                status = .updateAvailable(current: installed, latest: nil)
            } else {
                status = .installed(version: installed)
            }
        } catch {
            status = .error((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    func installZaDark() async {
        await runAction(verb: "Đang cài ZaDark") {
            if !self.brew.isInstalled() {
                throw ZaDarkHelperError.brewBootstrapRequired
            }
            try await self.brew.tap("quaric/zadark", onLine: self.loggingSink)
            try await self.brew.install("zadark", onLine: self.loggingSink)
            try await self.cli.install(onLine: self.loggingSink)
            if let info = ZaloVersionProbe.read() {
                self.prefsStorage.setLastPatchedZaloBuild(info.build)
            }
            self.applyAsarPatchIfEnabled()
        }
    }

    func uninstallZaDark() async {
        await runAction(verb: "Đang gỡ ZaDark") {
            try await self.cli.uninstall(onLine: self.loggingSink)
        }
    }

    func updateZaDark() async {
        await runAction(verb: "Đang cập nhật ZaDark") {
            _ = try await self.orchestrator.upgradeZaDarkAndRePatch(
                forceQuitZalo: self.preferences.forceQuitZaloDuringRePatch
            )
            self.applyAsarPatchIfEnabled()
        }
    }

    func rePatchNow(trigger: ReinstallOrchestrator.Trigger = .userRequested) async {
        await runAction(verb: "Đang áp lại ZaDark") {
            _ = try await self.orchestrator.rePatchIfNeeded(
                trigger: trigger,
                forceQuitZalo: self.preferences.forceQuitZaloDuringRePatch
            )
            self.applyAsarPatchIfEnabled()
        }
    }

    /// Repair a broken Zalo.app state by renaming `app.asar.bak` → `app.asar`.
    /// We have App Management TCC grant (this process), so the move succeeds where
    /// shell `mv` from an unprivileged Terminal would fail.
    func repairZalo() async {
        await runAction(verb: "Đang khôi phục Zalo") {
            let fm = FileManager.default
            let bak = URL(fileURLWithPath: ZaloVersionProbe.asarBackupPath)
            let asar = URL(fileURLWithPath: ZaloVersionProbe.asarPath)

            guard fm.fileExists(atPath: bak.path) else {
                throw ZaDarkHelperError.backupMissing
            }
            if fm.fileExists(atPath: asar.path) {
                // Not broken — nothing to do.
                self.appendSystemLog("Zalo.app đã có app.asar, không cần khôi phục.")
                return
            }
            try fm.moveItem(at: bak, to: asar)
            self.appendSystemLog("Đã khôi phục app.asar từ app.asar.bak.")
        }
    }

    func updatePreferences(_ new: Preferences) {
        let old = preferences
        preferences = new
        new.save()
        try? LoginItemService.set(enabled: new.launchAtLogin)

        // F1 — react to filename-fixer toggle
        if old.filenameFixerEnabled != new.filenameFixerEnabled {
            applyFilenameFixerPreference()
        }

        // F4 (deprecated) — toggle has no effect in v26.4.005+. Cleanup of
        // any prior injection happens at launch via cleanupDeprecatedAsarPatch.
    }

    // MARK: - F1: Filename Fixer

    /// Start/stop the Downloads watcher according to current preference.
    /// Idempotent — safe to call from start() and updatePreferences().
    func applyFilenameFixerPreference() {
        if preferences.filenameFixerEnabled {
            downloadWatcher.onRenamed = { [weak self] event in
                Task { @MainActor in self?.handleAutoRename(event: event) }
            }
            downloadWatcher.onTCCDenied = { [weak self] in
                Task { @MainActor in
                    self?.downloadFolderAccessDenied = true
                    self?.appendSystemLog("Downloads bị chặn (TCC). Cấp Full Disk Access để dùng tính năng sửa tên.")
                }
            }
            downloadWatcher.start()
            // Reaching here without the TCC fallback firing → access is OK.
            // Reset banner if it was previously stuck on.
            if !downloadFolderAccessDenied {
                // no-op — banner only set on actual denial
            }
        } else {
            downloadWatcher.stop()
            downloadFolderAccessDenied = false
        }
    }

    private func handleAutoRename(event: DownloadFolderWatcher.RenameEvent) {
        let originalName = event.originalURL.lastPathComponent
        let newName = event.newURL.lastPathComponent
        appendSystemLog("Sửa tên: \(originalName) → \(newName)")
        Task {
            await NotificationService.postRenameToast(
                originalName: originalName,
                fixedURL: event.newURL
            )
        }
    }

    /// Bulk-rename: scan ~/Downloads + rename every matching file. Called from
    /// PreferencesView "Quét + sửa file cũ" button.
    func scanDownloadsAndFix() async {
        guard !isBulkRenamingDownloads else { return }
        isBulkRenamingDownloads = true
        defer { isBulkRenamingDownloads = false }

        let folder = downloadWatcher.folderURL
        let result = await Task.detached(priority: .utility) {
            FilenameFixer.scanAndRename(in: folder)
        }.value

        lastBulkRenameCount = result.renamed
        if result.renamed > 0 {
            appendSystemLog("Quét Downloads: đã sửa \(result.renamed) tệp.")
            toastMessage = "Đã sửa \(result.renamed) tệp."
        } else {
            appendSystemLog("Quét Downloads: không có tệp nào cần sửa.")
            toastMessage = "Không có tệp nào cần sửa."
        }
        if !result.errors.isEmpty {
            appendSystemLog("Quét Downloads: \(result.errors.count) lỗi (bỏ qua).")
        }
    }

    /// Undo a previous rename — called by AppDelegate from the notification action.
    /// Best-effort: if file was already moved/deleted, log + ignore.
    func undoRename(currentPath: String, originalName: String) {
        let url = URL(fileURLWithPath: currentPath)
        do {
            try FilenameFixer.undoRename(currentURL: url, originalName: originalName)
            appendSystemLog("Hoàn tác đổi tên: \(url.lastPathComponent) → \(originalName)")
            toastMessage = "Đã hoàn tác."
        } catch {
            appendSystemLog("Hoàn tác lỗi: \(error.localizedDescription)")
        }
    }

    // MARK: - F2: Diagnostics & Quick Actions

    /// Run a full health check and store the snapshot. UI observes
    /// `lastHealthCheck` to render `HealthCheckCard` in the hero slot.
    func runHealthCheck() async {
        guard !isRunningHealthCheck else { return }
        isRunningHealthCheck = true
        defer { isRunningHealthCheck = false }
        appendSystemLog("Chạy kiểm tra hệ thống…")

        let snap = await HealthChecker.runAll(brew: brew, cli: cli)
        lastHealthCheck = snap
        appendSystemLog("Kiểm tra hoàn tất: \(snap.okCount)/\(snap.results.count) ổn.")
    }

    /// Quit Zalo (politely; force-fallback) then relaunch.
    func restartZalo() async {
        await runAction(verb: "Khởi động lại Zalo") {
            let wasRunning = ZaloVersionProbe.isRunning()
            if wasRunning {
                for app in ZaloVersionProbe.runningInstances() {
                    app.terminate()
                }
                // Wait briefly for graceful shutdown — fall back to force-kill.
                for _ in 0..<15 {
                    if !ZaloVersionProbe.isRunning() { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if ZaloVersionProbe.isRunning() {
                    for app in ZaloVersionProbe.runningInstances() {
                        app.forceTerminate()
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            _ = await ZaloLauncher.launch()
            self.appendSystemLog(wasRunning ? "Zalo đã khởi động lại." : "Zalo đã được mở.")
        }
    }

    /// Open `~/Library/Application Support/Zalo` in Finder. Path is stable;
    /// falls back to user's Library if Zalo subfolder doesn't exist yet.
    func revealZaloDataFolder() {
        let zaloPath = NSString(string: "~/Library/Application Support/Zalo").expandingTildeInPath
        let fallback = NSString(string: "~/Library/Application Support").expandingTildeInPath
        let target = FileManager.default.fileExists(atPath: zaloPath) ? zaloPath : fallback
        if target == fallback {
            appendSystemLog("Thư mục Zalo data chưa tồn tại — mở Application Support.")
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    /// Markdown-formatted diagnostics ready to paste into a GitHub issue.
    /// Replaces the older plaintext copyDiagnostics for users — keep both
    /// since copyDiagnostics is referenced from MainPopoverView's
    /// "Copy nhật ký" button (raw shell output) and this is the cleaner one
    /// for issue templates.
    func copyDiagnosticsMarkdown() -> String {
        let helperVersion = GitHubReleaseChecker.currentHelperVersion()
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        let zaloShort = zaloInfo?.shortVersion ?? "n/a"
        let zaloBuild = zaloInfo?.build ?? "n/a"
        let zadark = installedZaDarkVersion ?? "chưa cài"
        let lastBuild = prefsStorage.lastPatchedZaloBuild() ?? "n/a"

        var md = """
        ## Environment
        - macOS: \(macOS)
        - ZaDarkHelper: v\(helperVersion)
        - ZaDark CLI: \(zadark)
        - Zalo: v\(zaloShort) (build \(zaloBuild))

        ## Status
        - Brew: \(hasBrew ? "✓" : "✗")
        - app.asar: \(FileManager.default.fileExists(atPath: ZaloVersionProbe.asarPath) ? "✓" : "✗")
        - app.asar.bak: \(hasBackup ? "✓" : "✗")
        - App Management TCC: \(hasAppManagementPermission ? "granted" : "denied")
        - Last patched Zalo build: \(lastBuild)

        """

        if let snap = lastHealthCheck {
            md += "\n## Last health check (\(snap.okCount)/\(snap.results.count))\n"
            for r in snap.results {
                md += "- \(r.ok ? "✓" : "✗") **\(r.name)** — \(r.detail)\n"
            }
        }

        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "HH:mm:ss"
        let allSessions = sessions + (currentSession.map { [$0] } ?? [])
        if let last = allSessions.last {
            md += "\n## Latest log session\n```\n"
            let status: String
            switch last.finalStatus {
            case .success: status = "✓"
            case .error(let m): status = "✗ \(m)"
            case .none: status = "…"
            }
            let dur = last.duration.map { String(format: " (%.1fs)", $0) } ?? ""
            md += "[\(tsFormatter.string(from: last.startedAt))] \(last.verb)\(dur) \(status)\n"
            for line in last.lines.suffix(50) {
                let tag = line.stream == .stderr ? "ERR" : "OUT"
                md += "  \(tag) | \(line.text)\n"
            }
            md += "```\n"
        }

        md += "\n## Reproduce steps\n1. (please fill in)\n"
        return md
    }

    // MARK: - F3: Deferred helper update

    /// Cancel any in-flight deferred download/ready state. Called when the
    /// user clicks the manual "Cập nhật" button so the manual flow doesn't
    /// race with the deferred install.
    func cancelDeferredUpdate() async {
        await deferredUpdate.cancel()
    }

    // MARK: - F4 cleanup (deprecated approach)

    /// Remove any leftover v26.4.004 asar patch on launch. The hook never
    /// worked (Zalo uses native IPC, not Electron will-download) and ran
    /// too early (before app.whenReady). Cleanup is best-effort: skips if
    /// Zalo is running (asar locked) — patch will get wiped naturally on
    /// next `zadark install` anyway.
    private func cleanupDeprecatedAsarPatch() {
        asarPatchActive = false
        guard !ZaloVersionProbe.isRunning() else { return }
        guard ZaloPatchInjector.isPatched() else { return }
        do {
            let removed = try ZaloPatchInjector.removePatch()
            if removed {
                appendSystemLog("Đã gỡ patch app.asar v26.4.004 (deprecated).")
            }
        } catch {
            appendSystemLog("Gỡ patch deprecated lỗi: \(error.localizedDescription)")
        }
    }

    /// Compatibility shim — old code paths in installZaDark/updateZaDark/
    /// rePatchNow still call this. v26.4.005 makes it a no-op since the
    /// patch is deprecated; preference defaults OFF for new users.
    func applyAsarPatchIfEnabled() {
        // No-op. Kept for source compat with the call sites in install
        // flows; can be deleted in a future release once those are updated.
    }

    func copyDiagnostics() -> String {
        let header = """
        ZaDark Helper diagnostics
        Status: \(status)
        Zalo: \(zaloInfo?.shortVersion ?? "n/a") (build \(zaloInfo?.build ?? "n/a"))
        ZaDark: \(installedZaDarkVersion ?? "none")
        Brew: \(hasBrew ? "yes" : "no")
        Backup: \(hasBackup ? "yes" : "no")
        Permission: \(hasAppManagementPermission ? "ok" : "denied")

        """
        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "HH:mm:ss"

        var out = header
        let allSessions = sessions + (currentSession.map { [$0] } ?? [])
        for session in allSessions.suffix(20) {
            let status: String
            switch session.finalStatus {
            case .success: status = "✓"
            case .error(let m): status = "✗ \(m)"
            case .none: status = "…"
            }
            let duration = session.duration.map { String(format: " (%.1fs)", $0) } ?? ""
            out += "[\(tsFormatter.string(from: session.startedAt))] \(session.verb)\(duration) \(status)\n"
            for line in session.lines.suffix(100) {
                let tag = line.stream == .stderr ? "ERR" : "OUT"
                out += "  \(tag) | \(line.text)\n"
            }
            out += "\n"
        }
        return out
    }

    // MARK: - Internals

    private func startWatchers() {
        watcher.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleBundleEvent(event) }
        }
        watcher.start()

        workspace.onZaloLaunch = { [weak self] in
            Task { @MainActor in
                self?.watcher.recheckNow()
                await self?.refresh()
            }
        }
        workspace.onZaloQuit = { [weak self] in
            // F3 — try to install pending update when user closes Zalo.
            Task { @MainActor in
                guard let self else { return }
                guard self.preferences.autoInstallHelperUpdate else { return }
                self.appendSystemLog("Zalo đã thoát — kiểm tra cài đặt cập nhật helper.")
                await self.deferredUpdate.installNowIfReady()
            }
        }
        workspace.onWake = { [weak self] in
            Task { @MainActor in self?.scheduler.fireNow() }
        }
        workspace.start()

        // Wire scheduler tick to periodic update check.
        // Replacing the closure requires a fresh instance.
        let periodic = UpdateScheduler(onTick: { [weak self] in
            Task { @MainActor in await self?.runPeriodicChecks() }
        })
        periodic.start()
        // Keep a strong reference by assigning over the placeholder slot.
        // Swap is done via a trivial trick: timer we stored was never started.
        // Replace the reference in-place.
        withExtendedLifetime(periodic) { _ in }
        _schedulerRetained = periodic
    }

    // Strong retain for the real scheduler (see startWatchers).
    private var _schedulerRetained: UpdateScheduler?

    private func handleBundleEvent(_ event: ZaloBundleWatcher.Event) {
        switch event {
        case .disappeared:
            zaloInfo = nil
            status = .notInstalled
            appendSystemLog("Zalo.app đã biến mất khỏi /Applications")

        case .reappeared(let new):
            zaloInfo = new
            appendSystemLog("Zalo.app xuất hiện lại (v\(new.shortVersion) build \(new.build))")
            Task { await refresh() }

        case .changed(let new):
            zaloInfo = new
            appendSystemLog("Phát hiện Zalo cập nhật: v\(new.shortVersion) build \(new.build)")
            if preferences.autoRePatchOnZaloUpdate {
                Task {
                    do {
                        let outcome = try await self.orchestrator.rePatchIfNeeded(
                            trigger: .zaloVersionChanged,
                            forceQuitZalo: self.preferences.forceQuitZaloDuringRePatch
                        )
                        self.appendSystemLog("Auto re-patch: \(outcome)")
                        self.applyAsarPatchIfEnabled()
                        await self.refresh()
                        let relaunched: Bool
                        if case .rePatched(_, _, let r) = outcome { relaunched = r } else { relaunched = false }
                        await NotificationService.post(
                            title: "ZaDark đã áp lại",
                            body: relaunched
                                ? "Zalo v\(new.shortVersion) đã được patch và mở lại."
                                : "Zalo v\(new.shortVersion) đã được patch lại."
                        )
                    } catch {
                        self.appendSystemLog("Auto re-patch lỗi: \(error)")
                        await self.refresh()
                        // Failed auto-repatch needs user attention → surface popover.
                        self.onRequestSurface?()
                    }
                }
            } else {
                // User opted out of auto re-patch → show popover so they can click manually.
                Task { await refresh() }
                onRequestSurface?()
            }
        }
    }

    /// Public — also called by manual UI button beside primary action.
    /// Always refreshes status afterward so the hero card reflects the result.
    func checkForZaDarkUpdate() async {
        guard brew.isInstalled(),
              (try? await brew.installedVersion(of: "zadark")) != nil else { return }
        try? await brew.update(onLine: nil)
        // Use detailed variant so we can log raw stdout/stderr — needed when
        // brew works on CLI but the in-app probe disagrees (env / PATH /
        // tap-resolution gotchas).
        let outcome = (try? await brew.outdatedDetailed("zadark"))
            ?? (outdated: false, stdout: "<call threw>", stderr: "")
        appendSystemLog("brew outdated zadark → outdated=\(outcome.outdated) stdout=\"\(outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines))\" stderr=\"\(outcome.stderr.prefix(120))\"")
        let now = Date.now
        prefsStorage.setLastUpdateCheck(now)
        lastUpdateCheck = now
        if outcome.outdated, preferences.notifyOnZaDarkUpdate {
            await NotificationService.post(
                title: "ZaDark có bản mới",
                body: "Mở ZaDark Helper để cập nhật."
            )
        }
        await refresh()
    }

    /// Periodic timer also checks GitHub helper releases — split out so the
    /// manual button can call ZaDark-only without piggybacking helper check.
    func runPeriodicChecks() async {
        await checkForZaDarkUpdate()
        await checkForHelperUpdate()
    }

    /// Queries GitHub Releases for the helper itself. Updates `helperUpdate`
    /// and posts a notification (respecting user preference) when newer found.
    func checkForHelperUpdate() async {
        let result = await GitHubReleaseChecker.check()
        switch result {
        case .upToDate:
            helperUpdate = nil
        case .updateAvailable(_, let latest):
            let previous = helperUpdate?.tagName
            helperUpdate = latest
            if previous != latest.tagName {
                if preferences.notifyOnZaDarkUpdate {
                    await NotificationService.post(
                        title: "ZaDarkHelper có bản mới \(latest.tagName)",
                        body: "Mở popover để cập nhật một click."
                    )
                }
                // Newly seen version → auto-open popover so the banner is visible.
                onRequestSurface?()

                // F3 — opt-in: pre-download in background so install is instant
                // when Zalo quits (or immediately if user opted into force).
                if preferences.autoInstallHelperUpdate {
                    Task {
                        await self.deferredUpdate.armDownload(release: latest)
                        if self.preferences.autoInstallEvenWhenZaloRunning {
                            self.appendSystemLog("Auto-install (force) — không chờ Zalo thoát.")
                            await self.deferredUpdate.installNowIfReady()
                        } else {
                            self.appendSystemLog("Helper update v\(latest.tagName) đã tải — sẽ cài khi Zalo thoát.")
                        }
                    }
                }
            }
        case .failed(let err):
            appendSystemLog("Helper update check lỗi: \(err.localizedDescription)")
        }
    }

    private func runAction(verb: String, block: @escaping () async throws -> Void) async {
        openSession(verb: verb)
        status = .working(verb)
        do {
            try await block()
            closeSession(.success)
            toastMessage = "Hoàn tất."
            await refresh()
        } catch let e as ZaDarkHelperError {
            if case .permissionDenied = e { hasAppManagementPermission = false }
            closeSession(.error(e.errorDescription ?? "\(e)"))
            status = .error(e.errorDescription ?? "\(e)")
            toastMessage = e.errorDescription
        } catch {
            closeSession(.error("\(error)"))
            status = .error("\(error)")
            toastMessage = "\(error)"
        }
    }

    // MARK: - Log sessions

    private func openSession(verb: String) {
        // Close any dangling session first (shouldn't happen; defensive).
        if currentSession != nil { closeSession(.success) }
        currentSession = LogSession(
            verb: verb,
            startedAt: .now,
            endedAt: nil,
            finalStatus: nil,
            lines: []
        )
    }

    private func closeSession(_ finalStatus: LogSession.FinalStatus) {
        guard var session = currentSession else { return }
        session.endedAt = .now
        session.finalStatus = finalStatus
        sessions.append(session)
        if sessions.count > maxSessions {
            sessions.removeFirst(sessions.count - maxSessions)
        }
        currentSession = nil
    }

    private var loggingSink: @Sendable (ShellLine) -> Void {
        let box = WeakBox()
        box.state = self
        return { line in
            Task { @MainActor in
                box.state?.appendLog(line)
            }
        }
    }

    func appendLog(_ line: ShellLine) {
        let entry = LogLine(timestamp: .now, stream: line.stream, text: line.text)
        if currentSession != nil {
            currentSession?.lines.append(entry)
            // Trim within-session to avoid unbounded memory.
            if let count = currentSession?.lines.count, count > maxLogLines {
                currentSession?.lines.removeFirst(count - maxLogLines)
            }
        } else {
            // No active action — park under a "Logs" (background) session so watcher events still show.
            if sessions.last?.verb != "Logs" || sessions.last?.isFinished == true {
                var bg = LogSession(verb: "Logs", startedAt: .now, endedAt: nil, finalStatus: nil, lines: [])
                bg.lines.append(entry)
                sessions.append(bg)
            } else {
                sessions[sessions.count - 1].lines.append(entry)
            }
            if sessions.count > maxSessions {
                sessions.removeFirst(sessions.count - maxSessions)
            }
        }
    }

    func appendSystemLog(_ text: String) {
        appendLog(ShellLine(stream: .stdout, text: "[helper] \(text)"))
    }

    func clearLog() {
        sessions.removeAll()
        currentSession = nil
    }
}
