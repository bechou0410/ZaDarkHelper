import AppKit
import Foundation

/// Wraps the `zadark` CLI (installed via Homebrew tap `quaric/zadark`).
/// Supported subcommands: `install`, `uninstall`, `-v`.
struct ZaDarkCLI: Sendable {
    let shell: ShellRunning
    /// Optional override — when nil we resolve the binary fresh on every call.
    /// Resolving lazily matters: the CLI may not exist at AppState init time
    /// (user hasn't run `brew install zadark` yet). If we cached nil here,
    /// the very first install flow after brew succeeded would fail with
    /// `.zadarkBinaryMissing` despite the binary being on disk.
    private let binaryOverride: String?
    private let fm: FileManager

    init(
        shell: ShellRunning = ShellRunner(),
        binaryPath: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.shell = shell
        self.binaryOverride = binaryPath
        self.fm = fileManager
    }

    /// Lazily resolves the binary for each invocation.
    private var currentBinary: String? {
        binaryOverride ?? Self.resolveBinary(fileManager: fm)
    }

    /// Search order: brew prefix bin -> /opt/homebrew/bin -> /usr/local/bin.
    static func resolveBinary(fileManager: FileManager = .default) -> String? {
        var candidates: [String] = []
        if let prefix = BrewLocation.prefix(fileManager: fileManager) {
            candidates.append("\(prefix)/bin/zadark")
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/zadark",
            "/usr/local/bin/zadark"
        ])
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    func install(onLine: (@Sendable (ShellLine) -> Void)? = nil) async throws {
        try precheck()
        try await run(["install"], onLine: onLine)
    }

    func uninstall(onLine: (@Sendable (ShellLine) -> Void)? = nil) async throws {
        try await run(["uninstall"], onLine: onLine)
    }

    /// Parses `zadark -v` output. Returns raw version string (e.g. "1.2.3").
    func version() async throws -> String {
        let result = try await runCapturing(["-v"])
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Output often like "zadark 1.2.3" — return last token.
        return trimmed.split(separator: " ").last.map(String.init) ?? trimmed
    }

    // MARK: - Private

    private func precheck() throws {
        guard fm.fileExists(atPath: ZaloVersionProbe.bundlePath) else {
            throw ZaDarkHelperError.zaloNotFound
        }
        if ZaloVersionProbe.isRunning() {
            throw ZaDarkHelperError.zaloRunning
        }
    }

    private func requireBinary() throws -> String {
        guard let path = currentBinary else { throw ZaDarkHelperError.zadarkBinaryMissing }
        return path
    }

    @discardableResult
    private func run(_ args: [String], onLine: (@Sendable (ShellLine) -> Void)?) async throws -> ShellResult {
        let bin = try requireBinary()
        let result = try await shell.run(bin, args: args, env: nil, onLine: onLine)
        guard result.ok else {
            throw ZaDarkHelperError.classify(exit: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    private func runCapturing(_ args: [String]) async throws -> ShellResult {
        try await run(args, onLine: nil)
    }
}
