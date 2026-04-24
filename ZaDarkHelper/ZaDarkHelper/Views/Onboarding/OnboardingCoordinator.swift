import Foundation
import Observation

/// Step-machine for the 3-step onboarding flow.
/// Stored separately so step views can react independently.
@MainActor
@Observable
final class OnboardingCoordinator {

    enum Step: Int, CaseIterable {
        case welcome = 0
        case permissions
        case install
        case done
    }

    enum InstallState: Equatable {
        case pending
        case running
        case success
        case failed(String)
    }

    var currentStep: Step = .welcome
    var zaloConfirmed: Bool = ZaloVersionProbe.read() != nil
    var permissionGranted: Bool = false
    var installState: InstallState = .pending

    func next() {
        if let nextStep = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }

    func back() {
        if currentStep.rawValue > 0,
           let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    func skip() {
        currentStep = .done
    }

    /// Probes App Management permission by attempting to open `app.asar` for
    /// read-write. `isReadableFile` is NOT a valid test — TCC blocks writes,
    /// not reads. Reading inside /Applications/<app>.app is allowed by default.
    ///
    /// Opening `forUpdating` asks the kernel for O_RDWR without truncating.
    /// TCC intercepts the open() syscall and returns EPERM if the user hasn't
    /// granted App Management. The attempt itself also registers our app in
    /// System Settings → App Management so the user can toggle the switch.
    func probePermission() {
        let path = ZaloVersionProbe.asarPath
        guard FileManager.default.fileExists(atPath: path) else {
            permissionGranted = false
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            let handle = try FileHandle(forUpdating: url)
            try handle.close()
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
    }
}
