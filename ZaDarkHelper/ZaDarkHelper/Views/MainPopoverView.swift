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

    /// Brief header-icon feedback after user taps the refresh button.
    /// The actual "có bản mới" surface is HelperUpdateBannerView.
    enum CheckConfirmation: Equatable {
        case upToDate
        case updateAvailable
        case failed
    }

    var body: some View {
        Group {
            if showOnboarding {
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

            // `.id` keyed on the release tag forces SwiftUI to re-identify the
            // banner when helperUpdate flips nil↔non-nil, guaranteeing a fresh
            // evaluation even if the @Observable tracker missed the change.
            HelperUpdateBannerView()
                .id(state.helperUpdate?.tagName ?? "no-update")

            StatusHeroCard(checkOverride: heroCheckOverride)
            ActionPillButton()

            secondaryRow

            Divider()

            PreferencesView(onReplayOnboarding: {
                showOnboarding = true
            })

            LogDrawerView()

            FooterStrip()
        }
        .padding(DesignTokens.horizontalPadding)   // symmetric on all 4 edges
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

    /// Manual "check for updates" trigger. Icon flashes result briefly:
    /// green ✓ when up-to-date, orange ⬆ when update found (banner shows details),
    /// red ⚠ on failure. Baseline is rotating arrows icon.
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
        // Simple circle check for the header button — reserve seal.fill for
        // the hero card's "đang hoạt động" / "đã mới nhất" states where it
        // carries more visual weight.
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
        state.isCheckingForUpdate = true
        checkConfirmation = nil
        state.appendSystemLog("Kiểm tra cập nhật (thủ công)…")
        Task {
            // Enforce a minimum 3s loading state so user always sees the
            // "Đang kiểm tra…" feedback — even when the GitHub API returns
            // in <100ms (common with warm caches).
            let minLoadingNs: UInt64 = 3_000_000_000
            let start = DispatchTime.now()
            await state.checkForHelperUpdate()
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            if elapsedNs < minLoadingNs {
                try? await Task.sleep(nanoseconds: minLoadingNs - elapsedNs)
            }
            isCheckingForUpdate = false
            state.isCheckingForUpdate = false
            if let release = state.helperUpdate {
                checkConfirmation = .updateAvailable
                state.appendSystemLog("Có bản mới \(release.tagName) — banner đang hiện.")
            } else {
                checkConfirmation = .upToDate
                state.appendSystemLog("Đã là bản mới nhất v\(GitHubReleaseChecker.currentHelperVersion()).")
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            checkConfirmation = nil
        }
    }

    /// Derives a StatusHeroCard override from the current check state so the
    /// hero card visually reflects the check lifecycle.
    /// - While checking: show spinner + "Đang kiểm tra..."
    /// - After: "Đã mới nhất" briefly (upToDate) or nothing (updateAvailable —
    ///   banner takes over)
    private var heroCheckOverride: StatusHeroCard.CheckOverride? {
        if isCheckingForUpdate { return .checking }
        switch checkConfirmation {
        case .upToDate: return .upToDate
        case .failed: return .failed("Vui lòng thử lại.")
        case .updateAvailable, .none: return nil
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { _ = await ZaloLauncher.launch() }
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
