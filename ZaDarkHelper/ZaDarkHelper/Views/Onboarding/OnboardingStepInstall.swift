import SwiftUI

/// Step 3 — trigger `installZaDark()` and show live state.
struct OnboardingStepInstall: View {
    @Environment(AppState.self) private var state
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 40))
                .foregroundStyle(.purple)

            Text("Cài ZaDark").font(.title2).bold()

            Text("Nhấn nút để ZaDarkHelper tap quaric/zadark, cài zadark qua Homebrew, rồi patch Zalo.app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                runInstall()
            } label: {
                HStack {
                    if coordinator.installState == .running {
                        ProgressView().controlSize(.small)
                        Text("Đang cài…")
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Cài ZaDark ngay").bold()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(coordinator.installState == .running || coordinator.installState == .success)

            statusView

            Text("Có thể bỏ qua và cài sau từ popover chính.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch coordinator.installState {
        case .pending:
            EmptyView()
        case .running:
            label("Đang chạy…", icon: "hourglass", tint: .orange)
        case .success:
            label("Thành công! Đang chuyển sang bước cuối.", icon: "checkmark.circle.fill", tint: .green)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                label("Thất bại", icon: "xmark.octagon.fill", tint: .red)
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func label(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1))
        )
    }

    private func runInstall() {
        coordinator.installState = .running
        Task {
            await state.installZaDark()
            if case .installed = state.status {
                coordinator.installState = .success
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                coordinator.next()
            } else if case .error(let msg) = state.status {
                coordinator.installState = .failed(msg)
            } else {
                // stale or anything else that's non-error
                coordinator.installState = .success
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                coordinator.next()
            }
        }
    }
}
