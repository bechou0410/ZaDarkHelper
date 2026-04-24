import SwiftUI

/// Root popover. Composes hero, primary action, log drawer, footer.
/// Settings + log are both rendered as inline DisclosureGroups so the popover
/// reads as a single native menu — no floating cards, no custom animations.
struct MainPopoverView: View {
    @Environment(AppState.self) private var state
    @State private var showOnboarding = false
    @State private var startedOnce = false
    @State private var isCheckingForUpdate = false
    @State private var checkConfirmation: CheckConfirmation?

    /// Brief inline feedback after user taps the refresh icon.
    /// Auto-clears after a short timeout so the header returns to baseline.
    enum CheckConfirmation: Equatable {
        case upToDate
        case updateAvailable
        case failed
    }

    var body: some View {
        Group {
            if showOnboarding {
                // Inline onboarding — sheets from a MenuBarExtra popover tend
                // to dismiss the popover on focus changes. Render inline.
                OnboardingInline(onFinish: { showOnboarding = false })
            } else {
                mainContent
            }
        }
        .frame(width: DesignTokens.popoverWidth)
        .task {
            if !startedOnce {
                startedOnce = true
                state.start()
                if !state.preferences.hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
            header

            if !state.hasAppManagementPermission {
                OnboardingBannerView()
            }

            HelperUpdateBannerView()

            StatusHeroCard()
            ActionPillButton()

            secondaryRow

            Divider()

            // Tuỳ chọn — native DisclosureGroup pattern.
            PreferencesView(onReplayOnboarding: {
                showOnboarding = true
            })

            LogDrawerView()

            FooterStrip()
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.vertical, DesignTokens.sectionSpacing)
        // Kill SwiftUI's implicit layout animation when disclosures expand —
        // header + hero + action must stay static. Applied at the parent so
        // it cascades to both disclosure groups below.
        .transaction { $0.animation = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.purple)
                .font(.title3)
            Text("ZaDark Helper").font(.headline)
            Spacer()
            checkUpdateButton
        }
    }

    /// Manual "check for updates" trigger in the header.
    /// Shows spinner while checking, transient icon feedback on completion.
    @ViewBuilder
    private var checkUpdateButton: some View {
        Button {
            runCheckForUpdate()
        } label: {
            if isCheckingForUpdate {
                ProgressView().controlSize(.small)
            } else if let status = checkConfirmation {
                Image(systemName: iconName(for: status))
                    .foregroundStyle(iconColor(for: status))
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .disabled(isCheckingForUpdate)
        .help("Kiểm tra cập nhật")
    }

    private func iconName(for status: CheckConfirmation) -> String {
        switch status {
        case .upToDate: return "checkmark.circle.fill"
        case .updateAvailable: return "arrow.up.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func iconColor(for status: CheckConfirmation) -> Color {
        switch status {
        case .upToDate: return .green
        case .updateAvailable: return DesignTokens.warningOrange
        case .failed: return .red
        }
    }

    private func runCheckForUpdate() {
        isCheckingForUpdate = true
        checkConfirmation = nil
        Task {
            await state.checkForHelperUpdate()
            isCheckingForUpdate = false
            checkConfirmation = state.helperUpdate == nil ? .upToDate : .updateAvailable
            // Clear confirmation after 2.5s so header returns to baseline icon.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            checkConfirmation = nil
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 8) {
            Button {
                Task.detached { ZaloLauncher.launch() }
            } label: {
                Label("Mở Zalo", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.zaloInfo == nil)

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(state.copyDiagnostics(), forType: .string)
            } label: {
                Label("Copy nhật ký", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("Thoát") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
    }
}
