import Foundation

/// Abstraction for running external processes.
/// Protocol exists so tests can substitute a deterministic fake.
protocol ShellRunning: Sendable {
    @discardableResult
    func run(
        _ executable: String,
        args: [String],
        env: [String: String]?,
        onLine: (@Sendable (ShellLine) -> Void)?
    ) async throws -> ShellResult
}

struct ShellLine: Sendable, Equatable {
    enum Stream: Sendable { case stdout, stderr }
    let stream: Stream
    let text: String
}

struct ShellResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { exitCode == 0 }
}

/// Concrete Process-based runner. Streams lines live; also returns full buffers.
struct ShellRunner: ShellRunning {

    @discardableResult
    func run(
        _ executable: String,
        args: [String] = [],
        env: [String: String]? = nil,
        onLine: (@Sendable (ShellLine) -> Void)? = nil
    ) async throws -> ShellResult {

        try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let env { process.environment = env }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            let stdoutBox = LineBuffer(stream: .stdout, onLine: onLine)
            let stderrBox = LineBuffer(stream: .stderr, onLine: onLine)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                stdoutBox.ingest(data)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                stderrBox.ingest(data)
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutBox.flush()
                stderrBox.flush()
                cont.resume(returning: ShellResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdoutBox.fullText(),
                    stderr: stderrBox.fullText()
                ))
            }

            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

/// Accumulates bytes and splits on newlines. Thread-safe via NSLock.
private final class LineBuffer: @unchecked Sendable {
    private let stream: ShellLine.Stream
    private let onLine: (@Sendable (ShellLine) -> Void)?
    private var buffer = Data()
    private var full = Data()
    private let lock = NSLock()

    init(stream: ShellLine.Stream, onLine: (@Sendable (ShellLine) -> Void)?) {
        self.stream = stream
        self.onLine = onLine
    }

    func ingest(_ data: Data) {
        lock.lock()
        buffer.append(data)
        full.append(data)
        let newline: UInt8 = 0x0A
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: idx)
            buffer.removeSubrange(0...idx)
            if let s = String(data: lineData, encoding: .utf8) {
                let line = ShellLine(stream: stream, text: s)
                lock.unlock()
                onLine?(line)
                lock.lock()
            }
        }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        if !buffer.isEmpty, let s = String(data: buffer, encoding: .utf8), !s.isEmpty {
            let line = ShellLine(stream: stream, text: s)
            buffer.removeAll()
            lock.unlock()
            onLine?(line)
            return
        }
        lock.unlock()
    }

    func fullText() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: full, encoding: .utf8) ?? ""
    }
}
