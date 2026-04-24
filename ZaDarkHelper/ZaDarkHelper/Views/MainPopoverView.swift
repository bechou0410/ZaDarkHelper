import SwiftUI

/// Root popover. Composes hero, primary action, secondary row, log drawer, footer.
struct MainPopoverView: View {
    @Environment(AppState.self) private var state
    @State private var showPreferences = false
    @State private var showOnboarding = false
    @State private var startedOnce = false

    var body: some View {
        Group {
            if showOnboarding {
                // Inline onboarding — hosting as a sheet dismisses the MenuBarExtra popover
                // on focus changes. Rendering inline keeps the popover alive across steps.
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

            // Settings drops down from the header (dropdown-menu feel). Hero
            // card + action button stay visible underneath and get pushed
            // down smoothly as popover grows. On close, settings slides back
            // up into the header edge and the space collapses.
            if showPreferences {
                PreferencesView(
                    isPresented: $showPreferences,
                    onReplayOnboarding: {
                        showPreferences = false
                        showOnboarding = true
                    }
                )
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
                // clipped keeps sliding content from overflowing outside the
                // rounded card during the drop animation.
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous))
                .transition(dropdownTransition)
            }

            StatusHeroCard()
            ActionPillButton()

            secondaryRow

            Divider()

            LogDrawerView()

            FooterStrip()
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.vertical, DesignTokens.sectionSpacing)
        // Animate layout shifts of the whole popover content as settings
        // drops in/out. Spring gives a natural "drawer" feel; response 0.45s
        // is slower than before per user feedback ("hơi nhanh").
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showPreferences)
    }

    /// Dropdown-menu transition for settings panel.
    /// Combines vertical push (slides down from the header edge) with opacity
    /// fade. The popover itself grows to accommodate, and views below (hero
    /// card, action button) shift down smoothly as part of the VStack layout
    /// animation — giving a single "drawer opens" gesture.
    private var dropdownTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.purple)
                .font(.title3)
            Text("ZaDark Helper").font(.headline)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showPreferences.toggle()
                }
            } label: {
                Image(systemName: showPreferences ? "gearshape.fill" : "gearshape")
                    .foregroundStyle(showPreferences ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Tuỳ chọn")
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
