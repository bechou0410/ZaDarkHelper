import AppKit
import SwiftUI

/// Compact banner shown when a newer ZaDarkHelper release is available on GitHub.
/// Click opens the Releases page in default browser. User downloads manually —
/// helper does NOT auto-install itself (avoids self-replace race conditions).
struct HelperUpdateBannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let release = state.helperUpdate {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.up.app.fill")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.warningOrange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("ZaDarkHelper có bản \(release.tagName)")
                        .font(.caption.weight(.semibold))
                    Text("Bạn đang dùng v\(GitHubReleaseChecker.currentHelperVersion()) — bấm để xem changelog.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Button("Tải") {
                    NSWorkspace.shared.open(release.htmlURL)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignTokens.warningOrange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.warningOrange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DesignTokens.warningOrange.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}
