import AppKit
import SwiftUI

/// Manages the menu-bar `NSStatusItem` with split click behavior:
///   • left-click   → toggle SwiftUI popover (main UI)
///   • right-click  → NSMenu with quick actions (check-update, quit)
///
/// Why not `MenuBarExtra`: the SwiftUI API doesn't expose per-button split
/// actions — the click always shows the same content. Dropping down to AppKit
/// is the only way to route right-click separately without hacks.
@MainActor
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState
    private var iconObservation: NSKeyValueObservation?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // SwiftUI popover — NSPopover with animates=true auto-interpolates
        // contentSize changes. Smooth resize on settings toggle comes from a
        // combination of:
        //   1. animates = true (NSPopover frame interpolation)
        //   2. SwiftUI .transition()/.animation() in MainPopoverView for
        //      content crossfade/slide as size changes
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true

        // IMPORTANT: use .preferredContentSize so NSHostingController tracks
        // SwiftUI layout changes and updates popover size automatically.
        // Without this, toggling the inline settings panel (expand/collapse)
        // leaves the popover stuck at the largest height it ever rendered.
        let host = NSHostingController(
            rootView: MainPopoverView().environment(appState)
        )
        host.sizingOptions = [.preferredContentSize]
        self.popover.contentViewController = host

        super.init()

        configureButton()
        observeIconChanges()
    }

    // MARK: - Button setup

    private func configureButton() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: appState.menuBarIconName,
            accessibilityDescription: "ZaDarkHelper"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick(_:))
        // Receive both left + right clicks via same action (we dispatch inside).
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// AppState uses @Observable — simplest way to keep icon in sync without
    /// bridging to Combine is a lightweight polling approach via didChange.
    /// Since @Observable changes are observable only from within SwiftUI bodies,
    /// we fall back to an explicit `refreshIcon()` call after state changes.
    private func observeIconChanges() {
        // Refresh on a short timer — cheap (just reads a string + sets an image).
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIcon() }
        }
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let name = appState.menuBarIconName
        if button.image?.accessibilityDescription == name { return }
        button.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: name
        )
        button.image?.isTemplate = true
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        switch event?.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so clicks inside popover route to our process (not Finder).
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let check = NSMenuItem(
            title: "Kiểm tra cập nhật",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        check.target = self
        menu.addItem(check)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "Về ZaDarkHelper v\(GitHubReleaseChecker.currentHelperVersion())",
            action: nil,
            keyEquivalent: ""
        )
        about.isEnabled = false
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Thoát ZaDarkHelper",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        // Show then clear so a subsequent left-click opens popover not menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu actions

    @objc private func checkForUpdates() {
        Task { @MainActor in
            appState.appendSystemLog("Kiểm tra cập nhật (thủ công)…")
            await appState.checkForHelperUpdate()

            if let latest = appState.helperUpdate {
                // Open popover so user sees the banner immediately.
                if !popover.isShown { togglePopover() }
                appState.appendSystemLog("Có bản \(latest.tagName) — xem banner trong popover.")
            } else {
                // No update — notify briefly.
                let alert = NSAlert()
                alert.messageText = "ZaDarkHelper đã mới nhất"
                alert.informativeText = "Phiên bản đang dùng: v\(GitHubReleaseChecker.currentHelperVersion())"
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
