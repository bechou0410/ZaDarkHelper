import SwiftUI

/// Background fill for the hero card — status-driven LinearGradient over thin material.
struct StatusHeroGradient: View {
    let status: AppState.Status

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(.thinMaterial)
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(DesignTokens.gradient(for: status))
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .strokeBorder(DesignTokens.tint(for: status).opacity(0.25), lineWidth: 0.5)
        }
    }
}
