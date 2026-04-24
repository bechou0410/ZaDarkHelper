import Foundation

/// User preferences, persisted in UserDefaults via PreferencesStorage.
/// Defaults chosen for "it just works" first-run UX.
struct Preferences: Codable, Equatable {
    var launchAtLogin: Bool = true
    var autoRePatchOnZaloUpdate: Bool = true
    var notifyOnZaDarkUpdate: Bool = true
    var forceQuitZaloDuringRePatch: Bool = false
    var hasCompletedOnboarding: Bool = false

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
