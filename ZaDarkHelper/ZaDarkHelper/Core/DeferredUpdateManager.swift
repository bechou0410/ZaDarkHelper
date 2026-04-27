import Foundation

/// F3 — orchestrates opt-in deferred helper updates.
///
/// Flow when `Preferences.autoInstallHelperUpdate` is ON:
///   1. On launch, AppState detects a new release → calls `armDownload(release:)`.
///   2. We download the DMG to /tmp without installing.
///   3. After download succeeds, state becomes `.ready` and we wait for either:
///      - Zalo to quit (best UX — user just finished using it), OR
///      - 24h timeout (surface prompt to install now), OR
///      - Manual cancel (user clicked the in-app update banner instead).
///   4. On the trigger, install + relaunch via `HelperAutoUpdater.installFromDMG`.
///
/// All state transitions go through the actor; `state` is read on MainActor
/// for UI rendering via `currentState()`.
actor DeferredUpdateManager {

    enum State: Equatable, Sendable {
        case idle
        case downloading(tag: String)
        case ready(tag: String, dmgPath: String, downloadedAt: Date)
        case installing(tag: String)
        case failed(tag: String, message: String)
    }

    /// Notifies caller when state transitions to `.ready` or `.failed`.
    var onStateChanged: (@Sendable (State) -> Void)?

    private(set) var state: State = .idle
    private var release: GitHubReleaseChecker.Release?
    private var timeoutTask: Task<Void, Never>?

    /// Hour count before we surface a prompt instead of silently waiting.
    /// Per phase-03 spec — user shouldn't be left wondering for days.
    private let timeoutHours: Int = 24

    func currentState() -> State { state }

    /// Begin background download for the given release. No-op if we're
    /// already busy with the same tag.
    func armDownload(release: GitHubReleaseChecker.Release) async {
        switch state {
        case .downloading(let t), .ready(let t, _, _), .installing(let t):
            if t == release.tagName { return }
            // Different tag — cancel current and re-arm.
            await cancel()
        default: break
        }
        self.release = release
        state = .downloading(tag: release.tagName)
        notify()

        do {
            let path = try await HelperAutoUpdater.downloadOnly(release: release)
            state = .ready(tag: release.tagName, dmgPath: path, downloadedAt: .now)
            armTimeout()
            notify()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            state = .failed(tag: release.tagName, message: msg)
            notify()
        }
    }

    /// Called when WorkspaceObserver detects Zalo quit OR when the user opted
    /// into "install even when Zalo running" and the download just finished.
    /// Only acts when state is `.ready`.
    func installNowIfReady() async {
        guard case .ready(let tag, let path, _) = state else { return }
        state = .installing(tag: tag)
        timeoutTask?.cancel()
        timeoutTask = nil
        notify()
        do {
            try await HelperAutoUpdater.installFromDMG(path: path)
            // installFromDMG terminates the app — we won't reach here on success.
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            state = .failed(tag: tag, message: msg)
            notify()
        }
    }

    /// User canceled (clicked manual "Cập nhật" in banner, or toggled feature off).
    /// Cleans up the downloaded DMG and resets state.
    func cancel() async {
        if case .ready(_, let path, _) = state {
            try? FileManager.default.removeItem(atPath: path)
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        release = nil
        state = .idle
        notify()
    }

    /// Snapshot for the UI — includes the original release for banner copy.
    func snapshot() -> (state: State, release: GitHubReleaseChecker.Release?) {
        (state, release)
    }

    // MARK: - Private

    private func armTimeout() {
        timeoutTask?.cancel()
        let hours = timeoutHours
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(hours) * 3_600 * 1_000_000_000)
            await self?.handleTimeout()
        }
    }

    private func handleTimeout() async {
        // Don't auto-install on timeout — surface to user via state change.
        // (Phase-03 spec: prompt user "Đã sẵn sàng v… — cài ngay?")
        // We re-emit `.ready` so observers can respond; UI decides whether
        // to nudge harder via banner / notification.
        if case .ready = state {
            notify()
        }
    }

    private func notify() {
        let snapshot = state
        if let cb = onStateChanged {
            Task { cb(snapshot) }
        }
    }
}
