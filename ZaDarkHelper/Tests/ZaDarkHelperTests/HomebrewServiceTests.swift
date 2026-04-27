import XCTest
@testable import ZaDarkHelper

final class HomebrewServiceTests: XCTestCase {

    func test_installedVersion_parsesOutput() async throws {
        let fake = ShellRunnerFake()
        fake.stub(argsContain: "--versions", stdout: "zadark 1.2.3\n")
        let svc = HomebrewService(shell: fake, brewPath: "/opt/homebrew/bin/brew")
        let v = try await svc.installedVersion(of: "zadark")
        XCTAssertEqual(v, "1.2.3")
    }

    func test_installedVersion_returnsNil_whenNotInstalled() async throws {
        let fake = ShellRunnerFake()
        fake.stub(argsContain: "--versions", exit: 1)
        let svc = HomebrewService(shell: fake, brewPath: "/opt/homebrew/bin/brew")
        let v = try await svc.installedVersion(of: "zadark")
        XCTAssertNil(v)
    }

    func test_outdated_trueWhenStdoutNonEmpty() async throws {
        let fake = ShellRunnerFake()
        fake.stub(argsContain: "outdated", stdout: "zadark\n")
        let svc = HomebrewService(shell: fake, brewPath: "/opt/homebrew/bin/brew")
        let outdated = try await svc.outdated("zadark")
        XCTAssertTrue(outdated)
    }

    func test_outdated_falseWhenEmpty() async throws {
        let fake = ShellRunnerFake()
        fake.stub(argsContain: "outdated", stdout: "")
        let svc = HomebrewService(shell: fake, brewPath: "/opt/homebrew/bin/brew")
        let outdated = try await svc.outdated("zadark")
        XCTAssertFalse(outdated)
    }

    func test_install_throwsOnNonZeroExit() async {
        let fake = ShellRunnerFake()
        fake.stub(argsContain: "install", exit: 1, stderr: "boom")
        let svc = HomebrewService(shell: fake, brewPath: "/opt/homebrew/bin/brew")
        do {
            try await svc.install("zadark")
            XCTFail("expected throw")
        } catch let e as ZaDarkHelperError {
            if case .formulaInstallFailed = e { return }
            XCTFail("wrong error: \(e)")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_brewNotFound_propagates() async {
        let fake = ShellRunnerFake()
        let svc = HomebrewService(shell: fake, brewPath: nil)
        do {
            try await svc.install("zadark")
            XCTFail()
        } catch ZaDarkHelperError.brewNotFound {
            // expected
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
