import SwiftUI

/// Warning banner shown when a write to Zalo.app was blocked by TCC.
/// Links to System Settings → App Management so the user can grant access.
struct OnboardingBannerView: View {

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cần quyền App Management")
                    .font(.subheadline).bold()
                Text("macOS chặn helper ghi vào Zalo.app. Mở System Settings → Privacy & Security → App Management và bật ZaDark Helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Mở System Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
        )
    }
}
