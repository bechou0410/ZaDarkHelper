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

    /// v0.34 state: Transaction.disablesAnimations=true on setter.
    /// Kills DisclosureGroup's internal expand animation at the binding level.
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

                Divider().padding(.vertical, 2)

                toggleRow(
                    title: "Tự động sửa tên file Zalo",
                    subtitle: "bỏ tiền tố \"gen-h-\" trong Downloads",
                    systemImage: "wand.and.rays",
                    isOn: filenameFixerBinding
                )

                if state.preferences.filenameFixerEnabled {
                    if state.downloadFolderAccessDenied {
                        tccDeniedBanner
                    }
                    menuButton(
                        title: state.isBulkRenamingDownloads
                            ? "Đang quét…"
                            : "Quét + sửa file cũ trong Downloads",
                        systemImage: "magnifyingglass"
                    ) {
                        Task { await state.scanDownloadsAndFix() }
                    }
                    .disabled(state.isBulkRenamingDownloads)
                }

                // F4 (deprecated v26.4.004 → v26.4.005): asar patch approach
                // didn't work — Zalo uses native IPC for save, not Electron
                // will-download. Toggle hidden; cleanup runs on launch.

                Divider().padding(.vertical, 2)

                // F3 — Auto-install helper update on launch (opt-in).
                toggleRow(
                    title: "Tự động cài bản mới của ZaDarkHelper",
                    subtitle: "tải nền + cài khi thoát Zalo",
                    systemImage: "arrow.down.app.fill",
                    isOn: autoInstallBinding
                )

                if state.preferences.autoInstallHelperUpdate {
                    toggleRow(
                        title: "Cài ngay không chờ Zalo thoát",
                        subtitle: "có thể gián đoạn workflow",
                        systemImage: "exclamationmark.triangle.fill",
                        isOn: autoInstallForceBinding,
                        warning: true
                    )
                }

                Divider().padding(.vertical, 2)

                // F2 — Diagnostics group. Read-only checks + safe quick actions.
                sectionHeader("Chẩn đoán")
                menuButton(
                    title: state.isRunningHealthCheck
                        ? "Đang kiểm tra…"
                        : "Kiểm tra hệ thống",
                    systemImage: "stethoscope"
                ) {
                    Task { await state.runHealthCheck() }
                }
                .disabled(state.isRunningHealthCheck)

                menuButton(
                    title: "Khởi động lại Zalo",
                    systemImage: "arrow.clockwise.circle"
                ) {
                    Task { await state.restartZalo() }
                }

                menuButton(
                    title: "Mở thư mục dữ liệu Zalo",
                    systemImage: "folder"
                ) {
                    state.revealZaloDataFolder()
                }

                menuButton(
                    title: "Copy chẩn đoán cho GitHub issue",
                    systemImage: "doc.on.clipboard"
                ) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(state.copyDiagnosticsMarkdown(), forType: .string)
                    state.toastMessage = "Đã copy markdown chẩn đoán."
                }

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
    private var filenameFixerBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.filenameFixerEnabled },
            set: { v in mutate { $0.filenameFixerEnabled = v } }
        )
    }

    private var autoInstallBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.autoInstallHelperUpdate },
            set: { v in mutate { $0.autoInstallHelperUpdate = v } }
        )
    }
    private var autoInstallForceBinding: Binding<Bool> {
        Binding(
            get: { state.preferences.autoInstallEvenWhenZaloRunning },
            set: { v in mutate { $0.autoInstallEvenWhenZaloRunning = v } }
        )
    }

    // MARK: - TCC banner

    /// Inline orange banner that appears under the toggle when macOS denies
    /// us access to ~/Downloads. Tapping the link opens System Settings.
    @ViewBuilder
    private var tccDeniedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(DesignTokens.warningOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cần quyền truy cập Downloads")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.warningOrange)
                Text("Mở System Settings → Privacy & Security → Files and Folders")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Mở System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.warningOrange.opacity(0.12))
        )
        .padding(.vertical, 4)
    }

    private func mutate(_ transform: (inout Preferences) -> Void) {
        var prefs = state.preferences
        transform(&prefs)
        state.updatePreferences(prefs)
    }

    /// Mini section header — uppercase caption used to delimit logical groups
    /// inside the same DisclosureGroup (e.g. "Chẩn đoán").
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}
