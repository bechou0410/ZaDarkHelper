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
        }
    }

    func rePatchNow(trigger: ReinstallOrchestrator.Trigger = .userRequested) async {
        await runAction(verb: "Đang áp lại ZaDark") {
            _ = try await self.orchestrator.rePatchIfNeeded(
                trigger: trigger,
                forceQuitZalo: self.preferences.forceQuitZaloDuringRePatch
            )
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
        preferences = new
        new.save()
        try? LoginItemService.set(enabled: new.launchAtLogin)
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
        workspace.onWake = { [weak self] in
            Task { @MainActor in self?.scheduler.fireNow() }
        }
        workspace.start()

        // Wire scheduler tick to periodic update check.
        // Replacing the closure requires a fresh instance.
        let periodic = UpdateScheduler(onTick: { [weak self] in
            Task { @MainActor in await self?.checkForZaDarkUpdate() }
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

    private func checkForZaDarkUpdate() async {
        guard brew.isInstalled(),
              (try? await brew.installedVersion(of: "zadark")) != nil else { return }
        try? await brew.update(onLine: nil)
        let outdated = (try? await brew.outdated("zadark")) ?? false
        let now = Date.now
        prefsStorage.setLastUpdateCheck(now)
        lastUpdateCheck = now
        if outdated, preferences.notifyOnZaDarkUpdate {
            await NotificationService.post(
                title: "ZaDark có bản mới",
                body: "Mở ZaDark Helper để cập nhật."
            )
            await refresh()
        }

        // Also check GitHub for a newer ZaDarkHelper release.
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
            // No active action — park under a "Nền" (background) session so watcher events still show.
            if sessions.last?.verb != "Nền" || sessions.last?.isFinished == true {
                var bg = LogSession(verb: "Nền", startedAt: .now, endedAt: nil, finalStatus: nil, lines: [])
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
