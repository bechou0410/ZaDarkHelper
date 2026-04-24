import SwiftUI

/// Radial blur transition — view blurs as it fades in/out.
/// Applied in combination with `.opacity` + `.scale` to add depth during the
/// transition. Subtle: max 6pt blur radius so text never looks illegible.
struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    /// Blurs from 6pt down to 0pt on insert, 0pt up to 6pt on remove.
    static var blur: AnyTransition {
        .modifier(
            active: BlurModifier(radius: 6),
            identity: BlurModifier(radius: 0)
        )
    }
}
