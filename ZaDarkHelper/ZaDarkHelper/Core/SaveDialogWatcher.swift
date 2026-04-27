import AppKit
import ApplicationServices
import Foundation

/// Phase 1 (v26.4.006) — observe Zalo via macOS Accessibility API. When a
/// save dialog appears, walk the AX tree to find the filename text field and
/// LOG its current value. No rewrite yet — we want to verify in production
/// that we correctly detect the filename before enabling destructive
/// behavior (lesson from F4: don't ship without runtime verification).
///
/// Phase 2 (v26.4.007 if Phase 1 passes) will add `AXUIElementSetAttributeValue`
/// to overwrite the field, stripping `gen-{tag}-` prefix in place.
final class SaveDialogWatcher: @unchecked Sendable {

    /// Fired whenever a save panel is detected with a current filename.
    /// In Phase 1, AppState just logs the value. In Phase 2, callback
    /// can also invoke `rewriteFilename(...)` to mutate the field.
    var onSavePanelDetected: (@Sendable (DetectedSavePanel) -> Void)?

    /// Fired once if AX permission is missing at start time. UI surfaces
    /// a banner + System Settings deeplink.
    var onPermissionDenied: (@Sendable () -> Void)?

    /// Snapshot passed to the callback. Owns the AXUIElement so the field
    /// can be rewritten in Phase 2 (CFRetain'd via the AX C API).
    struct DetectedSavePanel: @unchecked Sendable {
        let filenameField: AXUIElement
        let currentFilename: String
        let pid: pid_t
    }

    // MARK: - Internals

    private let bundleID = ZaloVersionProbe.bundleIDFallback
    private var observer: AXObserver?
    private var attachedPID: pid_t?
    private var workspaceLaunchToken: NSObjectProtocol?
    private var workspaceTerminateToken: NSObjectProtocol?
    private let queue = DispatchQueue(label: "zadark.savedialog-watcher")

    // MARK: - Lifecycle

    func start() {
        guard Self.hasAccessibilityPermission() else {
            onPermissionDenied?()
            return
        }
        attachToZaloIfRunning()

        // Re-attach when user launches Zalo (Zalo may not be running on app start).
        let nc = NSWorkspace.shared.notificationCenter
        workspaceLaunchToken = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self?.bundleID else { return }
            self?.attachToZaloIfRunning()
        }
        workspaceTerminateToken = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self?.bundleID else { return }
            self?.detachObserver()
        }
    }

    func stop() {
        detachObserver()
        let nc = NSWorkspace.shared.notificationCenter
        if let t = workspaceLaunchToken { nc.removeObserver(t) }
        if let t = workspaceTerminateToken { nc.removeObserver(t) }
        workspaceLaunchToken = nil
        workspaceTerminateToken = nil
    }

    deinit { stop() }

    // MARK: - Public helpers

    /// Probes process trust without prompting. Use the prompting variant
    /// when user explicitly enables the toggle (so the OS dialog appears).
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompting variant — pass `true` from a user-initiated action to
    /// trigger the macOS "Allow ZaDarkHelper to control this computer"
    /// dialog. Returns current state synchronously; permission may flip
    /// to true after the user responds (re-check via `start()` later).
    static func requestAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Phase 2 helper — rewrite filename. Stub for now (Phase 1 doesn't call it).
    static func rewriteFilename(field: AXUIElement, to newValue: String) -> Bool {
        let cfValue = newValue as CFString
        let err = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, cfValue)
        return err == .success
    }

    // MARK: - Attach / detach

    private func attachToZaloIfRunning() {
        guard observer == nil else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let zalo = apps.first else { return }
        let pid = zalo.processIdentifier
        attachedPID = pid

        var localObserver: AXObserver?
        let createErr = AXObserverCreate(pid, axCallback, &localObserver)
        guard createErr == .success, let obs = localObserver else { return }

        let appEl = AXUIElementCreateApplication(pid)
        let refconPtr = Unmanaged.passUnretained(self).toOpaque()
        // Subscribe — kAXWindowCreatedNotification fires when any new window
        // (including save sheets) opens. kAXFocusedUIElementChangedNotification
        // helps catch the moment when filename field gets focus, which is
        // useful as a backup signal in case window-created fires too early.
        AXObserverAddNotification(obs, appEl, kAXWindowCreatedNotification as CFString, refconPtr)
        AXObserverAddNotification(obs, appEl, kAXFocusedUIElementChangedNotification as CFString, refconPtr)

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        observer = obs
    }

    private func detachObserver() {
        guard let obs = observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        observer = nil
        attachedPID = nil
    }

    // MARK: - AX callback handler

    fileprivate func handleAXEvent(element: AXUIElement) {
        // Search the element subtree for the save panel's filename field.
        // Heuristic: NSSavePanel filename field is an AXTextField whose
        // role description is typically "save panel name field" (localized).
        // Fall back to any focusable AXTextField inside a sheet/save dialog.
        guard let pid = attachedPID else { return }
        guard let field = findFilenameField(under: element) else { return }

        var rawValue: AnyObject?
        let getErr = AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &rawValue)
        guard getErr == .success, let str = rawValue as? String else { return }

        let snapshot = DetectedSavePanel(
            filenameField: field,
            currentFilename: str,
            pid: pid
        )
        onSavePanelDetected?(snapshot)
    }

    /// Recursive walk to find a likely save-panel filename text field.
    /// Bounded depth + breadth so we never hang on a pathological tree.
    private func findFilenameField(under root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 6 { return nil }   // save panel tree is shallow

        // Direct check: is this the filename text field?
        if isLikelyFilenameField(root) { return root }

        // Recurse into children.
        var rawChildren: AnyObject?
        let err = AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &rawChildren)
        guard err == .success, let children = rawChildren as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findFilenameField(under: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func isLikelyFilenameField(_ el: AXUIElement) -> Bool {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        guard let r = role as? String, r == kAXTextFieldRole else { return false }

        // Identifier check — NSSavePanel uses well-known identifiers in modern macOS.
        var identifier: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXIdentifierAttribute as CFString, &identifier)
        if let id = identifier as? String,
           id.lowercased().contains("savepanel")
            || id.lowercased().contains("filename")
            || id.lowercased().contains("name field") {
            return true
        }

        // Role description fallback (localized): "save panel name field"
        var roleDesc: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleDescriptionAttribute as CFString, &roleDesc)
        if let desc = roleDesc as? String,
           desc.lowercased().contains("save")
            || desc.lowercased().contains("lưu") {
            return true
        }

        // Generic fallback — any editable text field returning a value with
        // a file extension, OR matching gen- pattern, is a strong candidate.
        var value: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value)
        if let v = value as? String,
           v.lowercased().hasPrefix("gen-")
            || (v as NSString).pathExtension.count >= 2 && (v as NSString).pathExtension.count <= 5 {
            return true
        }

        return false
    }
}

// MARK: - C callback bridge

/// AXObserver requires a C function pointer; we bridge to the Swift method
/// via the `refcon` pointer (set when subscribing). Defensive guards so a
/// malformed event never crashes the helper.
private func axCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<SaveDialogWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.handleAXEvent(element: element)
}
