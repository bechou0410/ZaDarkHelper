import SwiftUI

/// Compact 2-line metadata strip at the bottom of the popover.
/// Line 1: ZaDark version + last update check timestamp.
/// Line 2: Zalo version/build + backup indicator.
struct FooterStrip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: ZaDarkHelper (app) version — read from bundle at runtime.
            HStack(spacing: 6) {
                Label("ZaDarkHelper v\(Self.helperVersion)", systemImage: "app.badge")
                Spacer(minLength: 6)
                if let last = state.lastUpdateCheck {
                    Text("kiểm tra \(Self.rel.localizedString(for: last, relativeTo: .now))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Line 2: ZaDark (patch) version
            HStack(spacing: 6) {
                if let v = state.installedZaDarkVersion {
                    Label("ZaDark v\(v)", systemImage: "moon.stars")
                } else {
                    Label("ZaDark chưa cài", systemImage: "moon")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Line 3: Zalo + backup indicator
            HStack(spacing: 6) {
                if let zalo = state.zaloInfo {
                    Label("Zalo v\(zalo.shortVersion)", systemImage: "message")
                    Text("(\(zalo.build))").foregroundStyle(.tertiary)
                } else {
                    Label("Không thấy Zalo", systemImage: "message.badge.filled.fill")
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 6)
                if state.hasBackup {
                    Label("có backup", systemImage: "externaldrive.badge.checkmark")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    /// Helper app version read from its own Info.plist. Falls back to "?" if
    /// the key isn't set (shouldn't happen in a real build).
    private static var helperVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()
}
