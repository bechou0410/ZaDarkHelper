import SwiftUI

/// Single-line footer with just ZaDarkHelper version + last update check.
/// ZaDark version is shown in the hero card's version chip; Zalo version is
/// shown beside it — no need to duplicate here.
struct FooterStrip: View {
    @Environment(AppState.self) private var state

    var body: some View {
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
    }

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
