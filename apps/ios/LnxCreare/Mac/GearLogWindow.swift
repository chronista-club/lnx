#if os(macOS)
import AppKit
import Observation
import SwiftUI

enum GearLogTab: String, CaseIterable, Identifiable {
    case flow = "流れ"
    case trace = "MIDI トレース"
    var id: String { rawValue }
}

@MainActor
@Observable
final class GearLogViewModel {
    let tail = GearLogTail()
    var tab: GearLogTab = .flow
    var query = ""
    var hideLibrary = true
    var hideClock = true
}

private let gearTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

struct GearLogWindow: View {
    let server: ServerMenuModel
    @Bindable var vm: GearLogViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $vm.tab) {
                    ForEach(GearLogTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                TextField("絞り込み（Gear・app・文字）", text: $vm.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                if vm.tab == .flow {
                    Toggle("通信ライブラリの行を隠す", isOn: $vm.hideLibrary)
                        .toggleStyle(.checkbox)
                } else {
                    Toggle("クロックを隠す", isOn: $vm.hideClock)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                Toggle(
                    "追従",
                    isOn: Binding(
                        get: { vm.tail.following },
                        set: { vm.tail.following = $0 }
                    )
                )
                .toggleStyle(.checkbox)
                Button("消去") { vm.tail.clear() }
                if vm.tab == .trace {
                    if server.tracing {
                        Button("トレースを止める") { server.stopTrace() }
                    } else {
                        Button("トレースを開始") { server.startTrace() }
                    }
                }
            }
            .padding(10)
            Divider()
            switch vm.tab {
            case .flow:
                GearFlowList(tail: vm.tail, query: vm.query, hideLibrary: vm.hideLibrary)
            case .trace:
                GearTraceTable(
                    tail: vm.tail,
                    query: vm.query,
                    tracing: server.tracing,
                    hideClock: vm.hideClock
                )
            }
        }
        .frame(minWidth: 820, minHeight: 360)
        .onAppear { vm.tail.start() }
        .onDisappear { vm.tail.stop() }
    }
}

struct GearFlowList: View {
    var tail: GearLogTail
    var query: String
    var hideLibrary: Bool

    var body: some View {
        let shown = tail.lines.filter {
            !isGearTraceLine($0)
                && (!hideLibrary || !isGearLibraryNoise($0))
                && gearLogMatches($0, query: query)
        }
        ScrollViewReader { proxy in
            List(shown) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(gearTimeFormatter.string(from: line.time))
                        .foregroundStyle(.secondary)
                    Text(line.level.rawValue)
                        .foregroundStyle(gearLogLevelColor(line.level))
                        .frame(width: 44, alignment: .leading)
                    Text(line.message)
                        .foregroundStyle(
                            line.level == .info ? .primary : gearLogLevelColor(line.level)
                        )
                        .textSelection(.enabled)
                }
                .font(.system(.callout, design: .monospaced))
                .id(line.id)
            }
            .onChange(of: shown.last?.id) { _, last in
                if tail.following, let last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = shown.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}

struct GearTraceTable: View {
    var tail: GearLogTail
    var query: String
    var tracing: Bool
    var hideClock: Bool

    var body: some View {
        let rows = tail.lines
            .filter { gearLogMatches($0, query: query) }
            .compactMap(gearTraceRow)
            .filter { !hideClock || !isGearClockRow($0) }
        if rows.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text(
                    tracing
                        ? "MIDI を待っています…（Gear を触ると行が流れます）"
                        : "トレースは止まっています。上の「トレースを開始」で記録が始まります"
                )
                .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                Table(rows) {
                    TableColumn("時刻") { r in
                        Text(gearTimeFormatter.string(from: r.time)).foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 100)
                    TableColumn("向き", value: \.direction).width(min: 60, ideal: 70)
                    TableColumn("Gear", value: \.gear).width(min: 70, ideal: 90)
                    TableColumn("app", value: \.app).width(min: 60, ideal: 80)
                    TableColumn("判定") { r in
                        Text(r.verdict).foregroundStyle(gearVerdictColor(r.verdict))
                    }
                    .width(min: 70, ideal: 110)
                    TableColumn("種類", value: \.kind).width(min: 60, ideal: 80)
                    TableColumn("バイト列") { r in
                        Text(r.detail).textSelection(.enabled)
                    }
                }
                .font(.system(.callout, design: .monospaced))
                .onChange(of: rows.last?.id) { _, last in
                    if tail.following, let last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = rows.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
}

func gearLogLevelColor(_ l: GearLogLevel) -> Color {
    switch l {
    case .error: return .red
    case .warn: return .orange
    case .info: return .secondary
    case .debug, .trace: return Color.secondary.opacity(0.6)
    }
}

func gearVerdictColor(_ v: String) -> Color {
    if v.hasPrefix("DROP") || v.hasPrefix("FAIL") || v.hasPrefix("OVERFLOW") {
        return .orange
    }
    if v.hasPrefix("OPEN") || v.hasPrefix("CLOSE") {
        return .secondary
    }
    return .primary
}
#endif
