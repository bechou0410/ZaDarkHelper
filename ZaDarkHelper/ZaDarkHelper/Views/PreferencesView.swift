import SwiftUI

/// Settings menu as a `DisclosureGroup` — mirrors the log drawer's
/// "> Nhật ký" pattern so the whole popover reads as one consistent menu.
/// No custom animation needed; DisclosureGroup handles the expand/collapse
/// transition natively, which also gives correct popover resize behavior.
struct PreferencesView: View {
    @Environment(AppState.self) private var state
    var onReplayOnboarding: (() -> Void)?
    @State private var expanded = false
    @State private var showUninstallConfirm = false

    /// easeInOut 0.5s on the binding setter — animates the disclosure content
    /// without touching NSPopover frame (popover stays animates=false).
    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expanded },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.5)) {
                    expanded = newValue
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: expandedBinding) {
            VStack(alignment: .leading, spacing: 2) {
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
                    title: "Tự động thoát Zalo khi cài đặt Zadark",
                    subtitle: "có thể mất phiên chat đang mở",
                    systemImage: "exclamationmark.triangle.fill",
                    isOn: forceQuitBinding,
                    warning: true
                )

                if let onReplayOnboarding {
                    Divider()
                        .padding(.vertical, 2)
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

                // Destructive action — kept at the bottom + confirmation dialog
                // so accidental click doesn't wipe ZaDark.
                Divider()
                    .padding(.vertical, 2)
                menuButton(
                    title: "Gỡ cài đặt ZaDark",
                    systemImage: "trash",
                    destructive: true
                ) {
                    showUninstallConfirm = true
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Tuỳ chọn", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
        }
        .alert("Gỡ cài đặt ZaDark?", isPresented: $showUninstallConfirm) {
            Button("Huỷ", role: .cancel) { }
            Button("Gỡ cài đặt", role: .destructive) {
                Task { await state.uninstallZaDark() }
            }
        } message: {
            Text("Zalo sẽ trở về giao diện sáng mặc định. ZaDark CLI vẫn giữ — có thể cài lại bất cứ lúc nào từ nút 'Cài ZaDark'.")
        }
    }

    // MARK: - Row builders

    /// Toggle row — leading icon + title (+ optional subtitle) + trailing switch.
    /// `warning: true` tints icon + title in warning-orange (for options user
    /// should think twice about — not fully destructive, just cautionary).
    @ViewBuilder
    private func toggleRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isOn: Binding<Bool>,
        warning: Bool = false
    ) -> some View {
        let accent: Color = warning ? DesignTokens.warningOrange : .primary
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout)
                    .frame(width: 18)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(accent)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 3)
    }

    /// Regular button row (icon + title + chevron).
    /// Destructive variant colors icon + title red for destructive actions.
    @ViewBuilder
    private func menuButton(
        title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout)
                    .frame(width: 18)
                    .foregroundStyle(destructive ? .red : .primary)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(destructive ? .red : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
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
