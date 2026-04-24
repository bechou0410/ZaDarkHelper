import Foundation
@testable import ZaDarkHelper

/// Deterministic stand-in for `ShellRunner`. Matches invocations by a script
/// of stubbed responses keyed on (executable, args).
final class ShellRunnerFake: ShellRunning, @unchecked Sendable {

    struct Stub {
        let matcher: (String, [String]) -> Bool
        let result: ShellResult
        let lines: [ShellLine]
    }

    private(set) var calls: [(exe: String, args: [String])] = []
    private var stubs: [Stub] = []

    func stub(
        exe: String? = nil,
        argsContain: String? = nil,
        exit: Int32 = 0,
        stdout: String = "",
        stderr: String = "",
        lines: [ShellLine] = []
    ) {
        stubs.append(Stub(
            matcher: { e, a in
                (exe.map { $0 == e } ?? true) &&
                (argsContain.map { needle in a.contains(where: { $0.contains(needle) }) } ?? true)
            },
            result: ShellResult(exitCode: exit, stdout: stdout, stderr: stderr),
            lines: lines
        ))
    }

    @discardableResult
    func run(
        _ executable: String,
        args: [String],
        env: [String: String]?,
        onLine: (@Sendable (ShellLine) -> Void)?
    ) async throws -> ShellResult {
        calls.append((executable, args))
        guard let hit = stubs.first(where: { $0.matcher(executable, args) }) else {
            return ShellResult(exitCode: 0, stdout: "", stderr: "")
        }
        for line in hit.lines { onLine?(line) }
        return hit.result
    }
}
