import AppKit
import Foundation

/// Coordinates the sequence: detect drift → optionally quit Zalo → run zadark install → persist marker.
/// An actor so we can't accidentally run two re-patches concurrently.
actor ReinstallOrchestrator {

    enum Trigger: Sendable {
        case zaloVersionChanged
        case userRequested
        case periodic
        case appLaunch
    }

    enum Outcome: Sendable, Equatable {
        case rePatched(zaloBuild: String, zadarkVersion: String?, relaunched: Bool)
        case alreadyCurrent
        case upgradedAndRePatched(from: String, to: String, zaloBuild: String, relaunched: Bool)
        case noZalo
    }

    private let brew: HomebrewService
    private let cli: ZaDarkCLI
    private let watcher: ZaloBundleWatcher?
    private let logSink: @Sendable (ShellLine) -> Void
    private let prefsStorage: PreferencesStorage
    private var isOrchestrating = false

    init(
        brew: HomebrewService,
        cli: ZaDarkCLI,
        watcher: ZaloBundleWatcher?,
        prefsStorage: PreferencesStorage = .init(),
        logSink: @escaping @Sendable (ShellLine) -> Void = { _ in }
    ) {
        self.brew = brew
        self.cli = cli
        self.watcher = watcher
        self.prefsStorage = prefsStorage
        self.logSink = logSink
    }

    func rePatchIfNeeded(trigger: Trigger, forceQuitZalo: Bool = false) async throws -> Outcome {
        guard !isOrchestrating else { return .alreadyCurrent }
        isOrchestrating = true
        defer {
            isOrchestrating = false
            watcher?.setSuspended(false)
        }

        watcher?.setSuspended(true)

        guard let info = ZaloVersionProbe.read() else {
            return .noZalo
        }

        let lastPatchedBuild = prefsStorage.lastPatchedZaloBuild()
        if trigger != .userRequested && lastPatchedBuild == info.build && ZaloVersionProbe.hasBackup() {
            return .alreadyCurrent
        }

        let wasRunning = ZaloVersionProbe.isRunning()
        if wasRunning {
            if forceQuitZalo {
                try await quitZalo(force: true)
            } else {
                throw ZaDarkHelperError.zaloRunning
            }
        }

        try await cli.install(onLine: logSink)

        prefsStorage.setLastPatchedZaloBuild(info.build)
        let zadarkVer = try? await cli.version()
        let relaunched = wasRunning ? await relaunchZalo() : false
        return .rePatched(zaloBuild: info.build, zadarkVersion: zadarkVer, relaunched: relaunched)
    }

    /// Update the Homebrew formula, then re-patch with the new binary.
    func upgradeZaDarkAndRePatch(forceQuitZalo: Bool = false) async throws -> Outcome {
        guard !isOrchestrating else { return .alreadyCurrent }
        isOrchestrating = true
        defer {
            isOrchestrating = false
            watcher?.setSuspended(false)
        }
        watcher?.setSuspended(true)

        let before = (try? await cli.version()) ?? "?"
        try await brew.update(onLine: logSink)
        try await brew.upgrade("zadark", onLine: logSink)
        let after = (try? await cli.version()) ?? "?"

        guard let info = ZaloVersionProbe.read() else { return .noZalo }

        let wasRunning = ZaloVersionProbe.isRunning()
        if wasRunning {
            if forceQuitZalo {
                try await quitZalo(force: true)
            } else {
                throw ZaDarkHelperError.zaloRunning
            }
        }

        try await cli.install(onLine: logSink)
        prefsStorage.setLastPatchedZaloBuild(info.build)
        let relaunched = wasRunning ? await relaunchZalo() : false
        return .upgradedAndRePatched(from: before, to: after, zaloBuild: info.build, relaunched: relaunched)
    }

    /// Flushes pending disk writes and opens Zalo.app.
    /// Returns true when NSWorkspace successfully launched it.
    /// Async all the way — no semaphore blocking the actor thread.
    private func relaunchZalo() async -> Bool {
        // Darwin sync() flushes FS buffers — guards against Zalo loading a stale app.asar.
        Darwin.sync()
        // Let the sync + NSRunningApplication termination fully settle before launching.
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await ZaloLauncher.launch()
    }

    /// Politely terminate Zalo. Escalates to forceTerminate after 3s timeout.
    func quitZalo(force: Bool) async throws {
        let apps = ZaloVersionProbe.runningInstances()
        guard !apps.isEmpty else { return }

        for app in apps {
            if force {
                app.forceTerminate()
            } else {
                app.terminate()
            }
        }

        // Wait up to 3s for graceful quit.
        for _ in 0..<30 {
            if ZaloVersionProbe.runningInstances().isEmpty { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if !force {
            for app in ZaloVersionProbe.runningInstances() {
                app.forceTerminate()
            }
        }
    }
}

/// Lightweight wrapper around UserDefaults for orchestration persistence.
/// Lives in the Core folder because both AppState and the orchestrator read it.
struct PreferencesStorage: Sendable {
    private let defaults: UserDefaults
    private let kLastPatchedBuild = "zadark.lastPatchedZaloBuild"
    private let kLastUpdateCheck = "zadark.lastUpdateCheck"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastPatchedZaloBuild() -> String? {
        defaults.string(forKey: kLastPatchedBuild)
    }

    func setLastPatchedZaloBuild(_ build: String) {
        defaults.set(build, forKey: kLastPatchedBuild)
    }

    func lastUpdateCheck() -> Date? {
        defaults.object(forKey: kLastUpdateCheck) as? Date
    }

    func setLastUpdateCheck(_ date: Date) {
        defaults.set(date, forKey: kLastUpdateCheck)
    }
}
