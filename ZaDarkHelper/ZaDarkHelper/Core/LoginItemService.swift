import Foundation
import ServiceManagement

/// Login-at-startup toggle using SMAppService (macOS 13+).
/// Uses the main app itself as the login item — no separate helper bundle required.
enum LoginItemService {

    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    /// Convenience: apply a bool preference, propagating any SM error.
    static func set(enabled: Bool) throws {
        if enabled {
            if !isEnabled() { try enable() }
        } else {
            if isEnabled() { try disable() }
        }
    }
}
