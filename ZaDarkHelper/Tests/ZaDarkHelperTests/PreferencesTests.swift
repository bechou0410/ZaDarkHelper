import XCTest
@testable import ZaDarkHelper

final class PreferencesTests: XCTestCase {

    private func ephemeralDefaults() -> UserDefaults {
        let name = "zadark.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_default_hasExpectedValues() {
        let p = Preferences.default
        XCTAssertTrue(p.launchAtLogin)
        XCTAssertTrue(p.autoRePatchOnZaloUpdate)
        XCTAssertTrue(p.notifyOnZaDarkUpdate)
        XCTAssertFalse(p.forceQuitZaloDuringRePatch)
        // F1: filename fixer is on by default; rename toast is OFF (added v26.5.004).
        XCTAssertTrue(p.filenameFixerEnabled)
        XCTAssertFalse(p.notifyOnFilenameRename)
    }

    func test_saveAndLoad_roundTrips() {
        let d = ephemeralDefaults()
        var p = Preferences.default
        p.launchAtLogin = false
        p.forceQuitZaloDuringRePatch = true
        p.save(to: d)

        let loaded = Preferences.load(from: d)
        XCTAssertEqual(loaded, p)
    }

    func test_load_returnsDefaultWhenEmpty() {
        let d = ephemeralDefaults()
        XCTAssertEqual(Preferences.load(from: d), Preferences.default)
    }
}
