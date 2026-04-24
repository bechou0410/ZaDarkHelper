import SwiftUI

/// Three dots at the top showing current step. Purely visual.
struct OnboardingProgressDots: View {
    let current: OnboardingCoordinator.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .fill(idx == current.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: idx == current.rawValue ? 10 : 8,
                           height: idx == current.rawValue ? 10 : 8)
            }
        }
    }
}
