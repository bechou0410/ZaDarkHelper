import SwiftUI

/// Settings menu rendered inline inside the main popover — no card, no backdrop,
/// just a clear header label + toggle rows so it reads as part of the panel.
struct PreferencesView: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    var onReplayOnboarding: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            // Toggles write through to persisted prefs on every change.
            toggleRow(
                title: "Chạy cùng macOS khi đăng nhập",
                systemImage: "power",
                isOn: launchAtLoginBinding
            )
            toggleRow(
                title: "Tự động áp lại khi Zalo cập nhật",
                systemImage: "arrow.clockwise",
                isOn: autoRePatchBinding
            )
            toggleRow(
                title: "Thông báo khi ZaDark có bản mới",
                systemImage: "bell.fill",
                isOn: notifyBinding
            )
            toggleRow(
                title: "Tự động thoát Zalo khi áp lại",
                subtitle: "có thể mất phiên chat đang mở",
                systemImage: "xmark.circle",
                isOn: forceQuitBinding,
                destructive: true
            )

            if let onReplayOnboarding {
                Divider()
                    .padding(.vertical, 4)

                menuButton(
                    title: "Xem lại hướng dẫn",
                    systemImage: "questionmark.circle"
                ) {
                    var prefs = state.preferences
                    prefs.hasCompletedOnboarding = false
                    state.updatePreferences(prefs)
                    onReplayOnboarding()
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Tuỳ chọn")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Menu rows

    /// Compact toggle row with leading icon + title (+ optional subtitle).
    /// Tappable everywhere on the row, not just on the switch.
    @ViewBuilder
    private func toggleRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isOn: Binding<Bool>,
        destructive: Bool = false
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 16)
                    .foregroundStyle(destructive ? .red : .primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(destructive ? .red : .primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.vertical, 2)
    }

    /// Regular tappable menu item (icon + title, no switch).
    @ViewBuilder
    private func menuButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 16)
                Text(title).font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
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
