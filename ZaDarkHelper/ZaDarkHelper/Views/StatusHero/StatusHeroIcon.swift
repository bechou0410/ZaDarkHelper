import SwiftUI

/// Hero icon: sized per DesignTokens, hierarchical symbol rendering, tinted
/// by status. Pure static rendering — no animation.
struct StatusHeroIcon: View {
    let status: AppState.Status
    let isBusy: Bool

    var body: some View {
        let tint = DesignTokens.tint(for: status)

        Image(systemName: DesignTokens.symbolName(for: status))
            .font(.system(size: DesignTokens.heroIconSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: DesignTokens.heroIconSize + 8, height: DesignTokens.heroIconSize + 8)
    }
}
