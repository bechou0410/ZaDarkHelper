import SwiftUI

/// Central visual tokens for the popover UI. One source of truth for sizes, colors, and gradients
/// so individual views stay focused on composition, not design decisions.
enum DesignTokens {

    // MARK: - Layout
    static let popoverWidth: CGFloat = 400
    static let horizontalPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12
    static let heroIconSize: CGFloat = 28
    static let heroPadding = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)

    // MARK: - Palette

    /// Deep burnt orange for warning actions (stale, brewMissing).
    /// System `.orange` leans yellow → white text contrast is poor.
    /// This RGB lands firmly in the orange-red zone so `.borderedProminent`
    /// renders white label text legibly in both light and dark mode.
    static let warningOrange = Color(red: 0.87, green: 0.42, blue: 0.06)

    // MARK: - Status-driven visuals
    static func tint(for status: AppState.Status) -> Color {
        switch status {
        case .installed: return .green
        case .updateAvailable: return warningOrange
        case .stale: return warningOrange
        case .brewMissing: return warningOrange
        case .broken: return .red
        case .error: return .red
        case .working: return .accentColor
        case .notInstalled, .initializing: return .secondary
        }
    }

    static func gradient(for status: AppState.Status) -> LinearGradient {
        // Subtle backdrop — enough tint to communicate state, low enough that
        // primary text stays readable in both light and dark mode.
        let base = tint(for: status).opacity(0.10)
        let tail = tint(for: status).opacity(0.015)
        return LinearGradient(
            colors: [base, tail],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func symbolName(for status: AppState.Status) -> String {
        switch status {
        case .initializing: return "hourglass"
        case .brewMissing: return "arrow.down.app.fill"
        case .notInstalled: return "moon"
        case .installed: return "checkmark.seal.fill"
        case .updateAvailable: return "arrow.up.circle.fill"
        case .stale: return "exclamationmark.triangle.fill"
        case .broken: return "bandage.fill"
        case .working: return "gearshape.2.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
