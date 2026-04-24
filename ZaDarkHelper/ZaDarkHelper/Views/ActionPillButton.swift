import SwiftUI

/// Large capsule-shaped primary button. Action and label derived from current state.
struct ActionPillButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            Task { await performAction() }
        } label: {
            HStack(spacing: 6) {
                if state.isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: actionIcon).font(.callout)
                }
                Text(actionLabel)
                    .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .clipShape(Capsule())
        .tint(actionTint)
        .disabled(isDisabled)
    }

    private func performAction() async {
        switch state.status {
        case .brewMissing:
            openTerminalForBrewBootstrap()
        case .notInstalled:
            await state.installZaDark()
        case .updateAvailable:
            await state.updateZaDark()
        case .stale:
            await state.rePatchNow()
        case .installed:
            await state.rePatchNow()
        case .broken:
            await state.repairZalo()
        case .error:
            await state.refresh()
        default:
            break
        }
    }

    private var actionLabel: String {
        switch state.status {
        case .initializing: return "Đang tải…"
        case .brewMissing: return "Cài Homebrew"
        case .notInstalled: return "Cài ZaDark"
        case .installed: return "Cài đặt lại ZaDark"
        case .updateAvailable: return "Cập nhật ZaDark"
        case .stale: return "Áp lại ZaDark ngay"
        case .broken: return "Khôi phục Zalo"
        case .working(let verb): return verb
        case .error: return "Thử lại"
        }
    }

    private var actionIcon: String {
        switch state.status {
        case .brewMissing: return "terminal.fill"
        case .notInstalled: return "arrow.down.circle.fill"
        case .updateAvailable: return "arrow.up.circle.fill"
        case .stale: return "arrow.clockwise.circle.fill"
        case .installed: return "arrow.clockwise"
        case .broken: return "bandage.fill"
        case .error: return "arrow.clockwise"
        default: return "circle"
        }
    }

    private var actionTint: Color {
        switch state.status {
        case .stale, .updateAvailable: return DesignTokens.warningOrange
        case .notInstalled: return .purple
        case .broken: return .red
        case .error: return .red
        default: return .accentColor
        }
    }

    private var isDisabled: Bool {
        if state.isBusy { return true }
        if case .initializing = state.status { return true }
        return false
    }

    private func openTerminalForBrewBootstrap() {
        let script = "tell application \"Terminal\" to do script \"\(BrewLocation.bootstrapCommand)\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
