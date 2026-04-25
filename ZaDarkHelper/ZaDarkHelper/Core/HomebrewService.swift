import Foundation

/// Wraps the `brew` CLI. All methods async; errors are typed via `ZaDarkHelperError`.
struct HomebrewService: Sendable {
    let shell: ShellRunning
    private let brewPath: String?

    init(shell: ShellRunning = ShellRunner(), brewPath: String? = BrewLocation.resolve()) {
        self.shell = shell
        self.brewPath = brewPath
    }

    func isInstalled() -> Bool { brewPath != nil }

    /// Add a tap (idempotent — brew tap re-runs silently).
    func tap(_ name: String, onLine: (@Sendable (ShellLine) -> Void)? = nil) async throws {
        let brew = try requireBrew()
        let result = try await shell.run(brew, args: ["tap", name], env: nil, onLine: onLine)
        guard result.ok else {
            throw ZaDarkHelperError.tapFailed(result.stderr)
        }
    }

    func install(_ formula: String, onLine: (@Sendable (ShellLine) -> Void)? = nil) async throws {
        let brew = try requireBrew()
        let result = try await shell.run(brew, args: ["install", formula], env: nil, onLine: onLine)
        guard result.ok else {
            throw ZaDarkHelperError.formulaInstallFailed(result.stderr)
        }
    }

    func update(onLine: (@Sendable (ShellLine) -> Void)? = nil) async throws {
        let brew = try requireBrew()
        let result = try await shell.run(brew, args: ["update"], env: nil, onLine: onLine)
        guard result.ok else {
            throw ZaDarkHelperError.commandFailed(exit: result.exitCode, stderr: result.stderr)
        }
    }

    func upgrade(_ formula: String, onLine: (@Sendable (ShellLine) -> Void)? = nil) async throws {
        let brew = try requireBrew()
        let result = try await shell.run(brew, args: ["upgrade", formula], env: nil, onLine: onLine)
        guard result.ok else {
            throw ZaDarkHelperError.formulaUpgradeFailed(result.stderr)
        }
    }

    /// Returns installed version string, or nil if not installed.
    func installedVersion(of formula: String) async throws -> String? {
        let brew = try requireBrew()
        let result = try await shell.run(brew, args: ["list", "--versions", formula], env: nil, onLine: nil)
        // exit 0 + empty stdout = installed but version missing (rare); exit 1 = not installed
        guard result.ok else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Output shape: "zadark 1.2.3"
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count == 2 ? parts[1] : nil
    }

    /// True if formula has a newer version available.
    /// Uses `brew outdated --quiet <formula>` — non-empty stdout = outdated.
    /// Returns the raw stdout too so the caller can log it for diagnostics
    /// (helper UI was reporting "đã mới nhất" while CLI showed outdated;
    /// without raw output it was impossible to trace).
    func outdated(_ formula: String) async throws -> Bool {
        let (isOutdated, _, _) = try await outdatedDetailed(formula)
        return isOutdated
    }

    func outdatedDetailed(_ formula: String) async throws -> (outdated: Bool, stdout: String, stderr: String) {
        let brew = try requireBrew()
        // Provide HOME explicitly — brew refuses to run without it. Inherit
        // the rest from the launching process so brew can locate its Cellar
        // and tap config like normal CLI.
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        let result = try await shell.run(brew, args: ["outdated", "--quiet", formula], env: env, onLine: nil)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (result.ok && !trimmed.isEmpty, result.stdout, result.stderr)
    }

    private func requireBrew() throws -> String {
        guard let brewPath else { throw ZaDarkHelperError.brewNotFound }
        return brewPath
    }
}
