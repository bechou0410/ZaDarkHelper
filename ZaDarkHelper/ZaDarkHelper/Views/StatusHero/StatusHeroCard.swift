import SwiftUI

/// Primary state summary card.
/// Layout (each on its own row for readability):
///   1. [icon] · title
///   2. subtitle
///   3. version chip (when relevant)
struct StatusHeroCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack(alignment: .topLeading) {
            StatusHeroGradient(status: state.status)

            HStack(alignment: .top, spacing: 12) {
                StatusHeroIcon(status: state.status, isBusy: state.isBusy)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Row 1 — title
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if state.isBusy {
                            ProgressView().controlSize(.small)
                        }
                    }

                    // Row 2 — subtitle (only when present)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Row 3 — version chip (only when present)
                    if case .hidden = state.versionChipContent {
                        EmptyView()
                    } else {
                        VersionChip(content: state.versionChipContent)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(DesignTokens.heroPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy

    private var title: String {
        switch state.status {
        case .initializing: return "Đang kiểm tra…"
        case .brewMissing: return "Cần cài Homebrew"
        case .notInstalled: return "Chưa cài ZaDark"
        case .installed: return "ZaDark đang hoạt động"
        case .updateAvailable: return "Có bản ZaDark mới"
        case .stale: return "Cần áp lại ZaDark"
        case .broken: return "Zalo đang hỏng"
        case .working(let verb): return verb
        case .error: return "Đã xảy ra lỗi"
        }
    }

    private var subtitle: String {
        switch state.status {
        case .initializing: return "Đang đọc trạng thái Zalo + Homebrew."
        case .brewMissing: return "Bấm nút dưới để mở Terminal và cài Homebrew."
        case .notInstalled: return "Bấm Cài ZaDark để tap quaric/zadark và patch Zalo."
        case .installed: return "Zalo đã được áp dark mode."
        case .updateAvailable: return "Cập nhật để nhận bản patch mới."
        case .stale: return "Zalo vừa cập nhật — áp lại để giữ dark mode."
        case .broken: return "app.asar bị thiếu. Bấm Khôi phục để trả bản gốc từ backup về."
        case .working: return "Đang thực hiện, vui lòng không tắt app."
        case .error(let msg): return msg
        }
    }
}
