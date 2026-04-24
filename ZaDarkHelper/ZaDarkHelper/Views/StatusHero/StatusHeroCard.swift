import SwiftUI

/// Primary state summary card.
/// Layout (each on its own row for readability):
///   1. [icon] · title
///   2. subtitle
///   3. version chip (when relevant)
struct StatusHeroCard: View {
    @Environment(AppState.self) private var state

    /// When set, hero temporarily shows update-check feedback instead of the
    /// regular app status. Set by MainPopoverView while user-triggered check
    /// is in flight or the result is still fresh.
    var checkOverride: CheckOverride?

    enum CheckOverride: Equatable {
        case checking
        case upToDate
        case failed(String)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Gradient follows the effective status (override takes priority)
            // so backdrop matches the icon — e.g. green check icon sits on a
            // subtle green-tinted gradient, not a stale gray one from the
            // underlying real status.
            StatusHeroGradient(status: effectiveStatus)

            HStack(alignment: .top, spacing: 12) {
                overrideOrStatusIcon
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Row 1 — title
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if state.isBusy {
                            ProgressView().controlSize(.small)
                        }
                    }

                    // Row 2 — subtitle (only when present)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Row 3 — chip row (ZaDark version + Zalo version side-by-side)
                    HStack(spacing: 6) {
                        if case .hidden = state.versionChipContent {
                            EmptyView()
                        } else {
                            VersionChip(content: state.versionChipContent)
                        }
                        if let zalo = state.zaloInfo {
                            zaloVersionChip(zalo)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(DesignTokens.heroPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived

    /// Maps the current checkOverride (if any) onto an AppState.Status value
    /// so all the status-driven visuals (gradient, border, tint) stay in sync
    /// with whatever the hero is actually showing. Without this mapping, the
    /// backdrop and the icon could use different colors.
    private var effectiveStatus: AppState.Status {
        switch checkOverride {
        case .checking: return .working("Đang kiểm tra cập nhật…")
        case .upToDate: return .installed(version: state.installedZaDarkVersion ?? "?")
        case .failed(let msg): return .error(msg)
        case .none: return state.status
        }
    }

    // MARK: - Icon row

    @ViewBuilder
    private var overrideOrStatusIcon: some View {
        switch checkOverride {
        case .checking:
            ProgressView()
                .controlSize(.large)
                .frame(width: DesignTokens.heroIconSize + 8, height: DesignTokens.heroIconSize + 8)
        case .upToDate:
            // Match StatusHeroIcon styling exactly — hierarchical rendering
            // gives the seal the same depth/layers look as when rendered for
            // the normal .installed status. Without this, the upToDate seal
            // is flat-filled and looks visually different despite same symbol.
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: DesignTokens.heroIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .frame(width: DesignTokens.heroIconSize + 8, height: DesignTokens.heroIconSize + 8)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DesignTokens.heroIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .frame(width: DesignTokens.heroIconSize + 8, height: DesignTokens.heroIconSize + 8)
        case .none:
            StatusHeroIcon(status: state.status, isBusy: state.isBusy)
        }
    }

    /// Small static chip showing Zalo's version alongside ZaDark's in the hero row.
    /// Rendered in blue tint so it reads as a context marker, not an action.
    private func zaloVersionChip(_ zalo: ZaloInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "message.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Zalo v\(zalo.shortVersion)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.blue.opacity(0.12)))
        .overlay(Capsule().stroke(Color.blue.opacity(0.28), lineWidth: 0.5))
        .foregroundStyle(Color.blue)
    }

    // MARK: - Copy

    private var title: String {
        // Override takes precedence — check feedback shown first.
        switch checkOverride {
        case .checking: return "Đang kiểm tra cập nhật…"
        case .upToDate: return "ZaDarkHelper đã mới nhất"
        case .failed: return "Không kiểm tra được"
        case .none:
            break
        }
        switch state.status {
        case .initializing: return "Đang kiểm tra…"
        case .brewMissing: return "Cần cài Homebrew"
        case .notInstalled: return "Chưa cài ZaDark"
        case .installed: return "ZaDark đang hoạt động"
        case .updateAvailable: return "Có bản ZaDark mới"
        case .stale: return "Cần áp lại ZaDark"
        case .broken: return "Zalo đang hỏng"
        case .working(let verb): return verb
        case .error: return "Đã xảy ra lỗi"
        }
    }

    private var subtitle: String {
        switch checkOverride {
        case .checking: return "Đang gọi GitHub Releases API…"
        case .upToDate: return "Phiên bản đang dùng: v\(GitHubReleaseChecker.currentHelperVersion())"
        case .failed(let msg): return msg
        case .none:
            break
        }
        switch state.status {
        case .initializing: return "Đang đọc trạng thái Zalo + Homebrew."
        case .brewMissing: return "Bấm nút dưới để mở Terminal và cài Homebrew."
        case .notInstalled: return "Bấm Cài ZaDark để tap quaric/zadark và patch Zalo."
        case .installed: return "Zalo đã được áp dark mode."
        case .updateAvailable: return "Cập nhật để nhận bản patch mới."
        case .stale: return "Zalo vừa cập nhật — áp lại để giữ dark mode."
        case .broken: return "app.asar bị thiếu. Bấm Khôi phục để trả bản gốc từ backup về."
        case .working: return "Đang thực hiện, vui lòng không tắt app."
        case .error(let msg): return msg
        }
    }
}
