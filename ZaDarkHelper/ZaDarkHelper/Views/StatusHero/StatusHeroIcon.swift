import SwiftUI

/// Hero icon: sized 40pt, multicolor rendering, pulse animation when the app is busy.
/// Respects the system Reduce Motion setting.
struct StatusHeroIcon: View {
    let status: AppState.Status
    let isBusy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = DesignTokens.tint(for: status)

        Image(systemName: DesignTokens.symbolName(for: status))
            .font(.system(size: DesignTokens.heroIconSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: DesignTokens.heroIconSize + 8, height: DesignTokens.heroIconSize + 8)
            .symbolEffect(.pulse, options: .repeating, isActive: isBusy && !reduceMotion)
    }
}
