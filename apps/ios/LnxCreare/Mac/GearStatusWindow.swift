#if os(macOS)
import AppKit
import SwiftUI

func gearPhaseColor(_ tone: GearPhaseTone) -> Color {
    switch tone {
    case .active: return .green
    case .waiting: return .yellow
    case .releasing: return .orange
    case .error: return .red
    case .off: return Color.secondary.opacity(0.5)
    }
}

/// 「どのアプリがどの Gear を使うか」のステータス一覧 window
struct GearStatusWindow: View {
    let model: ServerMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Icon.view(model.phase.isRunning ? .waveform : .waveformSlash, size: 18)
                Text(model.phase.title).font(.headline)
                Spacer()
                if let version = model.gearServiceVersion {
                    Text("lnx-server \(version)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            if let detail = model.phase.detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            if model.gearRows.isEmpty {
                Text(
                    model.phase.isRunning
                        ? "Gear の情報を待っています…"
                        : "lnx サーバが停止しているため、Gear の状態は分かりません"
                )
                .foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(model.gearRows) {
                    TableColumn("Gear") { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let maker = row.maker {
                                Text(maker).font(.caption).foregroundStyle(.tertiary)
                            }
                            Text(row.model)
                                .fontWeight(row.tone == .attention ? .semibold : .regular)
                                .foregroundStyle(row.tone == .quiet ? .secondary : .primary)
                        }
                        .help(row.id)
                    }
                    .width(min: 180, ideal: 230)
                    TableColumn("担当") { row in GearAppLabel(name: row.assignment) }
                        .width(min: 90, ideal: 120)
                    TableColumn("握っている") { row in GearAppLabel(name: row.holder) }
                        .width(min: 90, ideal: 120)
                    TableColumn("phase") { row in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(gearPhaseColor(gearPhaseTone(row.phase)))
                                .frame(width: 8, height: 8)
                            Text(row.phase)
                        }
                    }
                    .width(min: 110, ideal: 150)
                    TableColumn("注意") { row in
                        Text(row.note ?? "")
                            .foregroundStyle(row.tone == .attention ? Color.orange : Color.secondary)
                            .help(row.note ?? "")
                    }
                    .width(min: 220, ideal: 320)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 340, alignment: .topLeading)
    }
}

struct GearAppLabel: View {
    var name: String

    var body: some View {
        HStack(spacing: 5) {
            if let icon = AppIcons.shared.icon(for: name),
               !["なし", "—", "この画面", "？"].contains(name)
            {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(name)
        }
    }
}
#endif
