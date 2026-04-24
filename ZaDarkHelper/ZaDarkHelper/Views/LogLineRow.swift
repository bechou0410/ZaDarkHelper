import SwiftUI

/// One monospaced row inside a session. Terminal-style palette:
///   timestamp → dim gray
///   OUT tag   → green   (classic terminal output)
///   ERR tag   → red
///   text(out) → soft white
///   text(err) → soft red
struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text(timeString)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Self.timestampColor)
            Text(line.stream == .stderr ? "ERR" : "OUT")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(line.stream == .stderr ? Self.errColor : Self.outColor)
            Text(line.text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(line.stream == .stderr ? Self.errColor : Self.stdoutColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeString: String { Self.formatter.string(from: line.timestamp) }

    // MARK: - Terminal palette (approximates macOS Terminal "Basic" theme)

    private static let timestampColor = Color(white: 0.45)
    private static let outColor       = Color(red: 0.45, green: 0.85, blue: 0.55)   // green
    private static let errColor       = Color(red: 0.95, green: 0.40, blue: 0.45)   // red
    private static let stdoutColor    = Color(white: 0.92)                          // off-white

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
