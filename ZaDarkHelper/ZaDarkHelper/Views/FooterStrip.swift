import SwiftUI

/// Single-line footer with just ZaDarkHelper version, centered.
struct FooterStrip: View {

    var body: some View {
        HStack {
            Spacer()
            Label("ZaDarkHelper v\(Self.helperVersion)", systemImage: "app.badge")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private static var helperVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
