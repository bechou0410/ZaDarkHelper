import SwiftUI

/// Outer log drawer with filter toggles + scrollable list of session rows.
/// Latest session auto-expanded; older ones collapsed.
struct LogDrawerView: View {
    @Environment(AppState.self) private var state
    @State private var expanded = false

    /// Writes wrapped in `disablesAnimations = true` to suppress DisclosureGroup's
    /// built-in expand animation on both directions.
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
                sessionList
                actionsRow
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

    private var sessionList: some View {
        ScrollView {
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
                            Divider().padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actionsRow: some View {
        HStack {
            Spacer()
            Button("Xoá nhật ký") { state.clearLog() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(state.sessions.isEmpty && state.currentSession == nil)
        }
    }
}
