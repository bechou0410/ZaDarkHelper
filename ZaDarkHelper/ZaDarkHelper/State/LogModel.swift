import Foundation

/// One line of captured output from a child process (or helper-synthetic log).
struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stream: ShellLine.Stream
    let text: String
}

/// A grouping of log lines produced by a single high-level action (install, upgrade, re-patch, etc).
/// Sessions let the UI show structured history instead of a flat stream.
struct LogSession: Identifiable, Equatable {
    enum FinalStatus: Equatable {
        case success
        case error(String)
    }

    let id = UUID()
    let verb: String
    let startedAt: Date
    var endedAt: Date?
    var finalStatus: FinalStatus?
    var lines: [LogLine]

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    var isFinished: Bool { endedAt != nil }

    static func == (lhs: LogSession, rhs: LogSession) -> Bool {
        lhs.id == rhs.id &&
        lhs.verb == rhs.verb &&
        lhs.startedAt == rhs.startedAt &&
        lhs.endedAt == rhs.endedAt &&
        lhs.finalStatus == rhs.finalStatus &&
        lhs.lines == rhs.lines
    }
}
