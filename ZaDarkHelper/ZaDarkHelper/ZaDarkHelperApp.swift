import SwiftUI

/// App entry point. Menu-bar only (LSUIElement=YES in Info.plist).
/// Owns a single `AppState` that holds services and view state.
@main
struct ZaDarkHelperApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        // Arm watchers + run first refresh immediately at launch — do NOT wait
        // for the user to open the popover. Otherwise FSEvents isn't listening
        // and Zalo updates happening before the first click go undetected.
        Task { @MainActor in
            state.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environment(appState)
                .frame(width: DesignTokens.popoverWidth)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
