import SwiftUI

/// Compact pill showing version info or an upgrade diff.
/// Hidden when content resolves to `.hidden`.
enum VersionChipContent: Equatable {
    case upToDate(String)                           // "v26.2"
    case upgrade(current: String, latest: String)   // "26.2 → 26.3"
    case zaloDrift(old: String, new: String)        // "build 2035 → 2040"
    case hidden
}

struct VersionChip: View {
    let content: VersionChipContent

    var body: some View {
        switch content {
        case .hidden:
            EmptyView()
        case .upToDate(let v):
            pill(tint: .green) {
                // Plain checkmark for chip — seal.fill reserved for hero card.
                Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                Text("ZaDark v\(v)").font(.system(size: 10.5, weight: .medium, design: .monospaced))
            }

        case .upgrade(let current, let latest):
            pill(tint: DesignTokens.warningOrange) {
                Text("ZaDark v\(current)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                Text("v\(latest)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }

        case .zaloDrift(let old, let new):
            pill(tint: .orange) {
                Text("build \(old)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                Text(new)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }
        }
    }

    /// Compact pill. Smaller font + tighter padding for less visual weight.
    @ViewBuilder
    private func pill<Content: View>(
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(tint.opacity(0.28), lineWidth: 0.5)
        )
        .foregroundStyle(tint)
    }
}

extension AppState {
    /// Derives the VersionChip content from current state.
    var versionChipContent: VersionChipContent {
        switch status {
        case .installed(let v):
            return .upToDate(v)
        case .updateAvailable(let current, let latest):
            return .upgrade(current: current, latest: latest ?? "mới")
        case .stale(_, let lastBuild):
            if let last = lastBuild, let zalo = zaloInfo {
                return .zaloDrift(old: last, new: zalo.build)
            }
            return .hidden
        default:
            return .hidden
        }
    }
}
