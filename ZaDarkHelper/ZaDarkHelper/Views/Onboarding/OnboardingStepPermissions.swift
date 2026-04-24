import AppKit
import SwiftUI

/// Step 2 — App Management permission walkthrough + live status probe.
struct OnboardingStepPermissions: View {
    @Bindable var coordinator: OnboardingCoordinator

    // Timer to poll for permission grant while visible.
    @State private var probeTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Cấp quyền App Management").font(.title2).bold()

            Text("macOS Ventura+ chặn mọi app ghi vào /Applications. ZaDark cần quyền này để patch Zalo. Bấm nút bên dưới, tìm ZaDarkHelper trong danh sách và bật công tắc.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openSystemSettings()
            } label: {
                Label("Mở System Settings → App Management", systemImage: "arrow.up.forward.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 8) {
                Image(systemName: coordinator.permissionGranted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(coordinator.permissionGranted ? .green : .orange)
                Text(coordinator.permissionGranted ? "Đã có quyền đọc Zalo.app" : "Chưa phát hiện quyền — sẽ tự nhận sau khi bật")
                    .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )

            Text("Nếu Zalo chưa được cài, bước này có thể bỏ qua và cấp quyền sau.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear { startProbe() }
        .onDisappear { stopProbe() }
    }

    private func startProbe() {
        coordinator.probePermission()
        probeTimer?.invalidate()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in coordinator.probePermission() }
        }
    }

    private func stopProbe() {
        probeTimer?.invalidate()
        probeTimer = nil
    }

    private func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
        NSWorkspace.shared.open(url)
    }
}
