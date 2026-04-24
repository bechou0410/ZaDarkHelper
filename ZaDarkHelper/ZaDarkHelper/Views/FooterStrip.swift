import SwiftUI

/// Single-line footer with just ZaDarkHelper version, centered.
struct FooterStrip: View {

    var body: some View {
        HStack {
            Spacer()
            Label("ZaDarkHelper v\(Self.helperVersion)", systemImage: "app.badge")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
            Spacer()
        }
    }

    private static var helperVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
