#if os(macOS)
import AppKit
import SwiftUI

/// Mac 版の窓の id（メニューバーから開く）
enum LnxWindow {
    static let main = "main"
    static let pairing = "pairing"
    static let gearStatus = "gear-status"
    static let gearLog = "gear-log"
    static let gearDesk = "gear-desk"
}

/// メニューバーの lnx（裁定「midistageみたいに、LNXのメニューがあって」、todo mem_1CgiUS2HyVdxMAGfnfE3QX + Step 4 mem_1ChTQGKFcpBxpP2ArK6M9T）。
/// サーバの今、Gear の接続・使用権ステータス、MIDI トレース、ログ、iPad をペアリング、lnx creare の窓
struct LnxMenu: View {
    let model: ServerMenuModel
    var logs: GearLogViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.phase.title)
        if let detail = model.phase.detail {
            Text(detail)
        }
        if let gearSummary = model.gearSummaryLine {
            Text(gearSummary)
        }
        if let error = model.lastError {
            Text("失敗: \(error)")
        }
        if !BundledServer.isInstalled(Bundle.main.bundleURL) {
            Text("開発用のビルドです。常駐は mise run mac:install で入れた lnx creare から")
        }
        Divider()
        serverActions
            .disabled(model.busy)
        Divider()
        Button {
            show(LnxWindow.gearStatus)
        } label: {
            Label { Text("Gear ステータスを開く") } icon: { Icon.menuImage(.waveform) }
        }
        Button {
            show(LnxWindow.gearDesk)
        } label: {
            Label { Text("Gear & Desk（机配置）を開く") } icon: { Icon.menuImage(.appWindow) }
        }
        Button {
            logs.tab = .flow
            show(LnxWindow.gearLog)
        } label: {
            Label { Text("ログとトレースを開く") } icon: { Icon.menuImage(.fileText) }
        }
        if model.tracing {
            Button {
                logs.tab = .trace
                show(LnxWindow.gearLog)
            } label: {
                Label { Text("MIDI トレースを見る") } icon: { Icon.menuImage(.waveform) }
            }
            Button("MIDI トレースを止める") {
                model.stopTrace()
            }
        } else {
            Button("MIDI トレースを開始（開発用）") {
                model.startTrace()
                logs.tab = .trace
                show(LnxWindow.gearLog)
            }
        }
        Button { NSWorkspace.shared.open(BundledServer.logURL) } label: {
            Label { Text("ログを開く") } icon: { Icon.menuImage(.fileText) }
        }
        .disabled(!FileManager.default.fileExists(atPath: BundledServer.logURL.path))
        Divider()
        // QR は同じ Mac のサーバ（手元用 [::1]:12731）から取るので、動いているときだけ
        Button { show(LnxWindow.pairing) } label: {
            Label { Text("iPad をペアリング…") } icon: { Icon.menuImage(.qrCode) }
        }
        .disabled(!model.phase.isRunning)
        Button { show(LnxWindow.main) } label: {
            Label { Text("lnx creare の窓を開く") } icon: { Icon.menuImage(.appWindow) }
        }
        Divider()
        Button("lnx creare を終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// どの状態で何を出すかは ServerPhase.actions（試験はそちら）。server:install の常駐と壊れたビルドは案内（detail）だけ
    @ViewBuilder
    private var serverActions: some View {
        ForEach(model.phase.actions, id: \.self) { action in
            switch action {
            case .start:
                Button { Task { await model.start() } } label: {
                    Label { Text("開始") } icon: { Icon.menuImage(.play) }
                }
            case .stop:
                Button { Task { await model.stop() } } label: {
                    Label { Text(model.phase.stopTitle) } icon: { Icon.menuImage(.stop) }
                }
            case .restart:
                Button { Task { await model.restart() } } label: {
                    Label { Text("再起動") } icon: { Icon.menuImage(.arrowClockwise) }
                }
            case .openLoginItems:
                Button("ログイン項目を開く…") { BundledServer.openLoginItems() }
            }
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}

/// メニューバーのアイコン。サーバが動いているかを兼ねる
struct LnxMenuBarIcon: View {
    let running: Bool

    var body: some View {
        Icon.menuImage(running ? .waveform : .waveformSlash, size: 18)
            .accessibilityLabel(Self.accessibilityName(running: running))
    }

    /// 読み上げの名前。メニューバーの項目の名前にもなる（System Events で項目を確かめるときもこれ）
    nonisolated static func accessibilityName(running: Bool) -> String {
        running ? "lnx サーバ（動いています）" : "lnx サーバ（止まっています）"
    }
}

/// メニューバーの「iPad をペアリング」で開く窓。中身はホームのシートと同じ PairingOfferView
struct PairingWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        PairingOfferView { dismissWindow(id: LnxWindow.pairing) }
            .preferredColorScheme(.dark)
    }
}
#endif
