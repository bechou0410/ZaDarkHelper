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

            // Settings panel slot — one view visible at a time.
            // Animation design: symmetric scale + opacity + subtle blur using a
            // spring curve. Scale anchored to the top so the content feels
            // anchored to the gear button (not floating from center).
            // Spring response (~0.3s) matches NSPopover's internal resize
            // animation so content + frame move together → single smooth gesture.
            Group {
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
                    .transition(panelTransition)
                } else {
                    VStack(spacing: DesignTokens.sectionSpacing) {
                        StatusHeroCard()
                        ActionPillButton()
                    }
                    .transition(panelTransition)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showPreferences)

            secondaryRow

            Divider()

            LogDrawerView()

            FooterStrip()
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.vertical, DesignTokens.sectionSpacing)
    }

    /// Symmetric transition for the settings slot.
    /// Combines scale-from-top (0.94 → 1.0) with opacity + a tiny blur.
    /// Scale anchor = top because both the gear button trigger and the content
    /// above are at the top of the popover — animating from there feels more
    /// physical than floating from the center.
    private var panelTransition: AnyTransition {
        .scale(scale: 0.94, anchor: .top)
            .combined(with: .opacity)
            .combined(with: .blur)
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
