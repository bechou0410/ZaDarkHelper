import AppKit
import SwiftUI

/// Card shown in the main panel during / right after user taps the manual
/// "check for updates" button. Replaces the StatusHeroCard + ActionPillButton
/// area so the feedback is visible where user already looks for status info.
struct UpdateCheckCard: View {

    enum Phase: Equatable {
        case checking
        case upToDate(current: String)
        case updateAvailable(release: GitHubReleaseChecker.Release)
        case failed(String)
    }

    let phase: Phase
    var onDismiss: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(.thinMaterial)
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(tint.opacity(0.10))
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 0.5)

            HStack(alignment: .center, spacing: 12) {
                icon
                    .frame(width: DesignTokens.heroIconSize, height: DesignTokens.heroIconSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                actionButton
            }
            .padding(DesignTokens.heroPadding)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .checking:
            ProgressView().controlSize(.large)
        case .upToDate:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: DesignTokens.heroIconSize - 4, weight: .semibold))
                .foregroundStyle(.green)
        case .updateAvailable:
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: DesignTokens.heroIconSize - 4, weight: .semibold))
                .foregroundStyle(DesignTokens.warningOrange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DesignTokens.heroIconSize - 4, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    private var title: String {
        switch phase {
        case .checking: return "Đang kiểm tra cập nhật…"
        case .upToDate(let v): return "ZaDarkHelper đã là bản mới nhất"
        case .updateAvailable(let r): return "Có bản mới \(r.tagName)"
        case .failed: return "Không kiểm tra được"
        }
        // swift-lint: unused binding "v" tolerated for readability symmetry
    }

    private var subtitle: String? {
        switch phase {
        case .checking:
            return "Đang gọi GitHub Releases API…"
        case .upToDate(let v):
            return "Phiên bản đang dùng: v\(v)"
        case .updateAvailable(let r):
            return "Bạn đang dùng v\(GitHubReleaseChecker.currentHelperVersion()) — bấm Tải để cập nhật."
        case .failed(let msg):
            return msg
        }
    }

    private var tint: Color {
        switch phase {
        case .checking: return .accentColor
        case .upToDate: return .green
        case .updateAvailable: return DesignTokens.warningOrange
        case .failed: return .red
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .checking:
            EmptyView()
        case .updateAvailable(let release):
            Button {
                NSWorkspace.shared.open(release.htmlURL)
            } label: {
                Label("Tải", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignTokens.warningOrange)
        case .upToDate, .failed:
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Ẩn")
        }
    }
}
