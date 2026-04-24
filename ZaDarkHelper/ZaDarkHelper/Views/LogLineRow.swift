import SwiftUI

/// One monospaced row inside a session. Coloured red for stderr.
struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(line.stream == .stderr ? "ERR" : "OUT")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(line.stream == .stderr ? .red : .secondary)
            Text(line.text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(line.stream == .stderr ? .red : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeString: String {
        Self.formatter.string(from: line.timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
