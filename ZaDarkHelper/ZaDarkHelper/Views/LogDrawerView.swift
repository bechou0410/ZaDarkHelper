import SwiftUI

/// Outer log drawer with filter toggles + scrollable list of session rows.
/// Terminal-style dark frame, clear button sits inside the frame's top-right.
struct LogDrawerView: View {
    @Environment(AppState.self) private var state
    @State private var expanded = false

    /// v0.34 state: Transaction.disablesAnimations=true on setter.
    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expanded },
            set: { newValue in
                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) { expanded = newValue }
            }
        )
    }

    var body: some View {
        @Bindable var state = state

        DisclosureGroup(isExpanded: expandedBinding) {
            VStack(alignment: .leading, spacing: 6) {
                filterRow
                terminalFrame
            }
            .padding(.top, 4)
        } label: {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
            Text("Nhật ký")
            Text("(\(state.sessions.count + (state.currentSession == nil ? 0 : 1)) phiên)")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .font(.subheadline.weight(.medium))
    }

    private var filterRow: some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            Toggle("stdout", isOn: $state.showStdout)
                .toggleStyle(.switch)
                .controlSize(.small)
            Toggle("stderr", isOn: $state.showStderr)
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
        }
        .font(.callout)
    }

    /// Full-width terminal frame containing the scrollable session list +
    /// an in-frame clear button at the bottom-right. Forced dark colorScheme
    /// so child rows with `.primary` text render white.
    private var terminalFrame: some View {
        ZStack(alignment: .bottomTrailing) {
            // ScrollView fills the entire frame, clips overflow naturally.
            // Hide indicator — terminal aesthetic; user can scroll via trackpad.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    let sessions = state.sessionsForDisplay
                    if sessions.isEmpty {
                        Text("Chưa có nhật ký. Bấm một hành động ở trên để bắt đầu.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                            LogSessionRow(session: session, initiallyExpanded: idx == 0)
                            if idx < sessions.count - 1 {
                                Divider()
                                    .overlay(Color.white.opacity(0.1))
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(8)
                .padding(.bottom, 32)   // reserve space at bottom so button doesn't overlap
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            clearButton
                .padding(.bottom, 6)
                .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        // v0.42-style rounded frame — constrained within parent horizontal
        // padding, 6pt rounded corners clip scroll content correctly.
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
    }

    /// Compact clear-log button floating at bottom-right of the terminal frame.
    private var clearButton: some View {
        Button {
            state.clearLog()
        } label: {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(5)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(state.sessions.isEmpty && state.currentSession == nil)
        .help("Xoá nhật ký")
    }
}
