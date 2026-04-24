import SwiftUI

/// Single-line footer with just ZaDarkHelper version.
/// ZaDark + Zalo versions shown in hero chips, no duplication.
struct FooterStrip: View {

    var body: some View {
        HStack(spacing: 6) {
            Label("ZaDarkHelper v\(Self.helperVersion)", systemImage: "app.badge")
            Spacer(minLength: 6)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private static var helperVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
