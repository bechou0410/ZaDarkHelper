import SwiftUI

/// Inline settings panel. Presented inside the main popover (not a sheet)
/// so focus stays with MenuBarExtra and toggles don't dismiss the popover.
struct PreferencesView: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    var onReplayOnboarding: (() -> Void)?

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 10) {
            header

            // Bind directly to `state.preferences` so toggles write through to
            // persisted storage on every change (no "save" button needed, and
            // the popover never loses focus from a sheet dismissal).
            Toggle("Chạy cùng macOS khi đăng nhập", isOn: launchAtLoginBinding)
            Toggle("Tự động áp lại khi Zalo cập nhật", isOn: autoRePatchBinding)
            Toggle("Thông báo khi ZaDark có bản mới", isOn: notifyBinding)
            Toggle("Tự động thoát Zalo khi áp lại (có thể mất phiên chat)", isOn: forceQuitBinding)
                .foregroundStyle(.red)

            if let onReplayOnboarding {
                Divider()
                Button {
                    var prefs = state.preferences
                    prefs.hasCompletedOnboarding = false
                    state.updatePreferences(prefs)
                    onReplayOnboarding()
                } label: {
                    Label("Xem lại hướng dẫn", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.secondary)
            Text("Tuỳ chọn")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Đóng tuỳ chọn")
        }
    }

    // MARK: - Bindings (write-through to AppState)

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.launchAtLogin },
            set: { v in mutate { $0.launchAtLogin = v } }
        )
    }
    private var autoRePatchBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.autoRePatchOnZaloUpdate },
            set: { v in mutate { $0.autoRePatchOnZaloUpdate = v } }
        )
    }
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.notifyOnZaDarkUpdate },
            set: { v in mutate { $0.notifyOnZaDarkUpdate = v } }
        )
    }
    private var forceQuitBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.forceQuitZaloDuringRePatch },
            set: { v in mutate { $0.forceQuitZaloDuringRePatch = v } }
        )
    }

    private func mutate(_ transform: (inout Preferences) -> Void) {
        var prefs = state.preferences
        transform(&prefs)
        state.updatePreferences(prefs)
    }
}
