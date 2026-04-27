import SwiftUI

/// Diagnostics result card. Replaces the StatusHeroCard slot when a snapshot
/// is present. Mirrors the visual weight of the hero card so the swap reads
/// as the same "primary surface" with a different mode.
struct HealthCheckCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        guard let snap = state.lastHealthCheck else {
            return AnyView(EmptyView())
        }
        return AnyView(card(for: snap))
    }

    @ViewBuilder
    private func card(for snap: HealthCheckSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snap: snap)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(snap.results) { row in
                    resultRow(row)
                }
            }

            HStack {
                Spacer()
                Button("Đóng") {
                    state.lastHealthCheck = nil
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.heroPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(snap.allOK
                    ? Color.green.opacity(0.10)
                    : DesignTokens.warningOrange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    (snap.allOK ? Color.green : DesignTokens.warningOrange).opacity(0.30),
                    lineWidth: 0.5
                )
        )
    }

    @ViewBuilder
    private func header(snap: HealthCheckSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: snap.allOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(snap.allOK ? .green : DesignTokens.warningOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kiểm tra hệ thống")
                    .font(.subheadline.weight(.semibold))
                Text("\(snap.okCount)/\(snap.results.count) thành phần ổn")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func resultRow(_ row: HealthResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(row.ok ? .green : DesignTokens.warningOrange)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.callout.weight(.medium))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
