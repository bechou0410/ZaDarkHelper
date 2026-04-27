import Foundation

/// User preferences, persisted in UserDefaults via PreferencesStorage.
/// Defaults chosen for "it just works" first-run UX.
struct Preferences: Codable, Equatable {
    var launchAtLogin: Bool = true
    var autoRePatchOnZaloUpdate: Bool = true
    var notifyOnZaDarkUpdate: Bool = true
    var forceQuitZaloDuringRePatch: Bool = false
    var hasCompletedOnboarding: Bool = false

    /// F1 — auto-rename `gen-h-*.{jpg,png,…}` files dropped into ~/Downloads by Zalo.
    var filenameFixerEnabled: Bool = true

    /// F5 — Phase 1 (v26.4.006, log-only). Helper observes Zalo via macOS
    /// Accessibility API; when save dialog appears, logs detected filename.
    /// Purpose: verify our AX walker correctly finds the field BEFORE shipping
    /// rewrite logic in Phase 2. Default OFF — user opts in, grants AX
    /// permission, performs save once, reports back.
    var saveDialogWatcherEnabled: Bool = false

    /// F4 — DEPRECATED in v26.4.005. The asar patch approach was fundamentally flawed:
    /// (1) `session.fromPartition(...)` requires `app.whenReady()` first; our hook
    /// ran too early and threw silently, (2) Zalo's popup-viewer save uses native
    /// IPC (`downloadWithMultiSrc`), not `webContents.downloadURL()` — so
    /// `will-download` event never fires for the relevant save flow.
    /// FilenameFixer (rename-after-save) remains the only working approach.
    /// Default OFF + on-launch cleanup removes any previously-injected patch.
    var asarPatchEnabled: Bool = false

    /// F3 — opt-in: download new helper releases on launch and install when Zalo quits.
    var autoInstallHelperUpdate: Bool = false
    /// F3 — when ON together with `autoInstallHelperUpdate`, install immediately
    /// even if Zalo is running (skips the quit-wait gate).
    var autoInstallEvenWhenZaloRunning: Bool = false

    static let `default` = Preferences()

    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    static let storageKey = "zadark.preferences.v1"
}
