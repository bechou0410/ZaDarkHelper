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

    /// F4 — patch `app.asar/bootstrap.js` to strip prefix at save dialog.
    /// Default ON: fixes the bug at source so dialog shows correct name from start
    /// (FilenameFixer remains as fallback for race conditions / files saved before patch).
    var asarPatchEnabled: Bool = true

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
