import SwiftUI

/// Root popover. Composes hero, primary action, log drawer, footer.
/// Settings + log are both rendered as inline DisclosureGroups so the popover
/// reads as a single native menu — no floating cards, no custom animations.
struct MainPopoverView: View {
    @Environment(AppState.self) private var state
    @State private var showOnboarding = false
    @State private var startedOnce = false
    @State private var updateCheckPhase: UpdateCheckCard.Phase?

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
        // Mirror background-detected helper updates into the same card the
        // manual check uses, so there's one consistent surface.
        .onChange(of: state.helperUpdate) { _, new in
            if let release = new {
                if updateCheckPhase == nil {
                    updateCheckPhase = .updateAvailable(release: release)
                }
            } else {
                if case .updateAvailable = updateCheckPhase {
                    updateCheckPhase = nil
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

            // Main status area: UpdateCheckCard takes over whenever a helper
            // update is detected (manual check OR background). Single source
            // of truth — no separate banner to duplicate the Tải button.
            if let phase = updateCheckPhase {
                UpdateCheckCard(phase: phase, onDismiss: { updateCheckPhase = nil })
            } else {
                StatusHeroCard()
                ActionPillButton()
            }

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

    /// Manual "check for updates" trigger in the header. Shows rotating arrows
    /// icon baseline; disabled while a check is in flight (main panel's
    /// UpdateCheckCard handles the actual feedback rendering).
    @ViewBuilder
    private var checkUpdateButton: some View {
        Button {
            runCheckForUpdate()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(isChecking)
        .help("Kiểm tra cập nhật")
    }

    private var isChecking: Bool {
        if case .checking = updateCheckPhase { return true }
        return false
    }

    private func runCheckForUpdate() {
        updateCheckPhase = .checking
        Task {
            await state.checkForHelperUpdate()
            if let release = state.helperUpdate {
                updateCheckPhase = .updateAvailable(release: release)
                // Keep card visible — user needs to act on it.
            } else {
                updateCheckPhase = .upToDate(current: GitHubReleaseChecker.currentHelperVersion())
                // Auto-dismiss after 3s so hero card comes back.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .upToDate = updateCheckPhase {
                    updateCheckPhase = nil
                }
            }
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
