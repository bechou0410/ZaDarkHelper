import SwiftUI

/// Step 1 — welcome + confirm Zalo is installed.
struct OnboardingStepWelcome: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Chào mừng đến ZaDark Helper")
                .font(.title2).bold()

            Text("Mini app này tự động áp dark mode cho Zalo PC và giữ nó luôn được áp dụng mỗi khi Zalo cập nhật.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            bulletRow("message.fill", "Dùng ZaDark chính thức qua Homebrew (quaric/zadark)")
            bulletRow("arrow.triangle.2.circlepath", "Tự động patch lại khi Zalo cập nhật")
            bulletRow("bell.fill", "Thông báo khi ZaDark có bản mới")

            Divider()

            Toggle(isOn: $coordinator.zaloConfirmed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tôi đã cài Zalo PC")
                    Text("/Applications/Zalo.app \(ZaloVersionProbe.read() == nil ? "(chưa thấy)" : "(đã thấy)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private func bulletRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 18)
            Text(text).font(.callout)
        }
    }
}
