import SwiftUI

/// Mac / iPad 共通の Gear カタログ & 机配置（desk.kdl）ビュー
struct GearDeskView: View {
    var onClose: (() -> Void)?
    @State private var selectedDeskName = "home"
    @State private var selectedGearID: String?

    private var currentDesk: DeskLayout {
        DeskPresets.all.first { $0.name == selectedDeskName } ?? DeskPresets.home
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gear & Desk")
                        .font(.title2.weight(.semibold))
                    Text("机配置（desk.kdl）と Gear の実寸（mm）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Desk", selection: $selectedDeskName) {
                    Text("home（家・\(DeskPresets.home.gears.count) Gear）").tag("home")
                    Text("studio（スタジオ・\(DeskPresets.studio.gears.count) Gear）").tag("studio")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                if let onClose {
                    Button("閉じる") { onClose() }
                        .accessibilityIdentifier("gearDesk.close")
                }
            }

            DeskBlueprintCanvas(desk: currentDesk, selectedGearID: $selectedGearID)
                .frame(minHeight: 280, maxHeight: 380)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))

            Text("この机の Gear（\(currentDesk.gears.count) 台）")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(currentDesk.gears) { placed in
                        let entry = GearCatalog.entry(for: placed.id)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if let maker = entry?.maker {
                                        Text(maker)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry?.model ?? placed.id)
                                        .font(.body.weight(.medium))
                                }
                                Text(
                                    "surface: \(placed.surface) · pos: (\(Int(placed.posX)), \(Int(placed.posZ))) mm · yaw: \(Int(placed.yaw))°"
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let entry {
                                Text(
                                    "\(Int(entry.widthMM))×\(Int(entry.depthMM))×\(Int(entry.heightMM)) mm"
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                Text(entry.hasModel3D ? "3D あり" : "箱表示")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        (entry.hasModel3D ? Color.accentColor : Color.secondary)
                                            .opacity(0.2),
                                        in: Capsule()
                                    )
                            }
                        }
                        .padding(10)
                        .background(
                            (selectedGearID == placed.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .onTapGesture {
                            selectedGearID = placed.id
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 540)
    }
}

/// 机と棚（surface）と Gear の実寸上面図を描くキャンバス（単位 mm、x = 右 +、z = 手前 +）
private struct DeskBlueprintCanvas: View {
    let desk: DeskLayout
    @Binding var selectedGearID: String?

    var body: some View {
        GeometryReader { geo in
            let fp = desk.footprint
            let pad: CGFloat = 24
            let availW = max(1, geo.size.width - pad * 2)
            let availH = max(1, geo.size.height - pad * 2)
            let scale = min(availW / max(1, CGFloat(fp.width)), availH / max(1, CGFloat(fp.depth)))
            let cx = geo.size.width / 2
            let cz = geo.size.height / 2

            ZStack {
                ForEach(desk.surfaces) { surface in
                    let sx = cx + CGFloat(surface.centerX - fp.centerX) * scale
                    let sz = cz + CGFloat(surface.centerZ - fp.centerZ) * scale
                    let sw = CGFloat(surface.width) * scale
                    let sd = CGFloat(surface.depth) * scale
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(surface.elevation > 780 ? 0.09 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .frame(width: sw, height: sd)
                        .position(x: sx, y: sz)
                }

                ForEach(desk.gears) { placed in
                    let entry = GearCatalog.entry(for: placed.id)
                    let w = CGFloat(entry?.widthMM ?? 120) * scale
                    let d = CGFloat(entry?.depthMM ?? 90) * scale
                    let gx = cx + CGFloat(placed.posX - fp.centerX) * scale
                    let gz = cz + CGFloat(placed.posZ - fp.centerZ) * scale
                    let isSelected = selectedGearID == placed.id

                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isSelected
                                    ? Color.accentColor.opacity(0.45)
                                    : Color.accentColor.opacity(0.22)
                            )
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                isSelected ? Color.accentColor : Color.white.opacity(0.55),
                                lineWidth: isSelected ? 2 : 1
                            )
                        Text(placed.id)
                            .font(.system(size: max(9, min(12, w * 0.16)), weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(width: max(18, w), height: max(14, d))
                    .rotationEffect(.degrees(-placed.yaw))
                    .position(x: gx, y: gz)
                    .onTapGesture {
                        selectedGearID = placed.id
                    }
                }
            }
        }
    }
}
