import SwiftUI

/// Collapsible session container. Shows verb + status icon + duration in header;
/// session lines in body filtered by `showStdout` / `showStderr`.
struct LogSessionRow: View {
    @Environment(AppState.self) private var state
    let session: LogSession
    @State private var expanded: Bool

    init(session: LogSession, initiallyExpanded: Bool = false) {
        self.session = session
        self._expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            let visible = filteredLines
            if visible.isEmpty {
                Text("Không có dòng nào khớp bộ lọc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visible) { LogLineRow(line: $0) }
                }
                .padding(.top, 4)
            }
        } label: {
            header
        }
        .padding(.vertical, 2)
    }

    private var filteredLines: [LogLine] {
        session.lines.filter { line in
            switch line.stream {
            case .stdout: return state.showStdout
            case .stderr: return state.showStderr
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .font(.caption)

            // Verb in terminal-cyan accent — mimics shell prompt coloring.
            Text(session.verb)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Self.accentCyan)

            Text(Self.timeFormatter.string(from: session.startedAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Self.dimGray)

            if let d = session.duration {
                Text(String(format: "%.1fs", d))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Self.dimGray)
            } else if !session.isFinished {
                ProgressView().controlSize(.mini)
            }

            Spacer(minLength: 6)

            Text("\(session.lines.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Self.dimGray)
        }
    }

    private static let accentCyan = Color(red: 0.45, green: 0.80, blue: 0.95)
    private static let dimGray    = Color(white: 0.55)

    private var statusIcon: String {
        switch session.finalStatus {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .none: return "gearshape.2.fill"
        }
    }

    private var statusTint: Color {
        switch session.finalStatus {
        case .success: return .green
        case .error: return .red
        case .none: return .orange
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
