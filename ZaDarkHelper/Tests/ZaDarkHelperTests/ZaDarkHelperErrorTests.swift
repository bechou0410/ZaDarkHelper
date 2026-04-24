import XCTest
@testable import ZaDarkHelper

final class ZaDarkHelperErrorTests: XCTestCase {

    func test_classify_permissionDenied() {
        let e = ZaDarkHelperError.classify(exit: 1, stderr: "write: Operation not permitted")
        XCTAssertEqual(e, .permissionDenied)
    }

    func test_classify_backupMissing() {
        let e = ZaDarkHelperError.classify(exit: 1, stderr: "app.asar.bak: no such file")
        XCTAssertEqual(e, .backupMissing)
    }

    func test_classify_zaloNotFound() {
        let e = ZaDarkHelperError.classify(exit: 1, stderr: "/Applications/Zalo.app: no such file")
        XCTAssertEqual(e, .zaloNotFound)
    }

    func test_classify_fallsBackToCommandFailed() {
        let e = ZaDarkHelperError.classify(exit: 7, stderr: "weird happened")
        if case .commandFailed(let code, _) = e {
            XCTAssertEqual(code, 7)
        } else {
            XCTFail("wrong case: \(e)")
        }
    }
}
