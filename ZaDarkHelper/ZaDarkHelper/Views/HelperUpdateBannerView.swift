import AppKit
import SwiftUI

/// Banner shown when a newer ZaDarkHelper release is on GitHub.
/// Primary action = auto-install (download DMG, replace /Applications/ZaDarkHelper.app, relaunch).
/// Secondary link = open Releases page in browser (fallback / review changelog).
struct HelperUpdateBannerView: View {
    @Environment(AppState.self) private var state
    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case updating
        case failed(String)
    }

    var body: some View {
        if let release = state.helperUpdate {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "arrow.up.app.fill")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.warningOrange)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ZaDarkHelper có bản \(release.tagName)")
                            .font(.caption.weight(.semibold))
                        Text("Bạn đang dùng v\(GitHubReleaseChecker.currentHelperVersion())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)

                    button(for: release)
                }

                if case .failed(let msg) = phase {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(release.htmlURL)
                    } label: {
                        Label("Xem changelog", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption2)

                    if release.dmgAsset == nil {
                        Text("· không có DMG để tự cài")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
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

    @ViewBuilder
    private func button(for release: GitHubReleaseChecker.Release) -> some View {
        if release.dmgAsset == nil {
            // No DMG asset → fall back to opening browser.
            Button("Tải thủ công") {
                NSWorkspace.shared.open(release.htmlURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignTokens.warningOrange)
        } else if phase == .updating {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Đang cập nhật…").font(.caption2)
            }
        } else {
            Button {
                runUpdate(release: release)
            } label: {
                Label("Cập nhật", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignTokens.warningOrange)
        }
    }

    private func runUpdate(release: GitHubReleaseChecker.Release) {
        phase = .updating
        Task {
            do {
                try await HelperAutoUpdater.performUpdate(release: release)
                // performUpdate terminates the app on success; this line is unreached.
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
