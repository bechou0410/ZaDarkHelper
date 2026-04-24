import SwiftUI

/// Inline alternative to `OnboardingSheet`.
/// Presented directly inside the MenuBarExtra popover so focus never leaves the
/// popover window — avoids the auto-dismiss issue that a .sheet triggers.
struct OnboardingInline: View {
    @Environment(AppState.self) private var state
    @State private var coordinator = OnboardingCoordinator()
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.vertical, 14)
            Divider()
            navRow
        }
        .frame(width: DesignTokens.popoverWidth)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            OnboardingProgressDots(current: coordinator.currentStep)
            Spacer()
            Button {
                coordinator.skip()
                finish()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Bỏ qua")
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.currentStep {
        case .welcome:
            OnboardingStepWelcome(coordinator: coordinator)
        case .permissions:
            OnboardingStepPermissions(coordinator: coordinator)
        case .install:
            OnboardingStepInstall(coordinator: coordinator)
        case .done:
            doneView
        }
    }

    private var doneView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.purple)
            Text("Sẵn sàng!").font(.headline)
            Text("ZaDarkHelper sẽ tiếp tục chạy ở menu bar. Có thể xem lại hướng dẫn này trong Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var navRow: some View {
        HStack(spacing: 8) {
            if coordinator.currentStep != .welcome && coordinator.currentStep != .done {
                Button("Quay lại") { coordinator.back() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if coordinator.currentStep != .done {
                Button("Bỏ qua") {
                    coordinator.skip()
                    finish()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }

            Spacer()

            switch coordinator.currentStep {
            case .welcome:
                Button("Tiếp theo") { coordinator.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!coordinator.zaloConfirmed)
            case .permissions:
                Button("Tiếp theo") { coordinator.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .install:
                Button("Hoàn tất") { coordinator.next() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .done:
                Button("Xong") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Finish

    private func finish() {
        var prefs = state.preferences
        prefs.hasCompletedOnboarding = true
        state.updatePreferences(prefs)
        onFinish()
    }
}
