#if os(macOS)
import AppKit
import SwiftUI

/// Mac 版の窓の id（メニューバーから開く）
enum LnxWindow {
    static let main = "main"
    static let pairing = "pairing"
}

/// メニューバーの LNX（裁定「midistageみたいに、LNXのメニューがあって」、todo mem_1CgiUS2HyVdxMAGfnfE3QX）。
/// サーバの今、開始・停止・再起動、ログ、iPad をペアリング、lnx creare の窓
struct LnxMenu: View {
    let model: ServerMenuModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.phase.title)
        if let detail = model.phase.detail {
            Text(detail)
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
        Button { NSWorkspace.shared.open(BundledServer.logURL) } label: {
            Label { Text("ログを開く") } icon: { Icon.menuImage(.fileText) }
        }
        .disabled(!FileManager.default.fileExists(atPath: BundledServer.logURL.path))
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
            .accessibilityLabel(running ? "LNX サーバ（動いています）" : "LNX サーバ（止まっています）")
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
