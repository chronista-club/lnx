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

    @ViewBuilder
    private var serverActions: some View {
        switch model.phase {
        case .running:
            Button { Task { await model.stop() } } label: {
                Label { Text("停止（ログイン時にも立ち上げない）") } icon: { Icon.menuImage(.stop) }
            }
            Button { Task { await model.restart() } } label: {
                Label { Text("再起動") } icon: { Icon.menuImage(.arrowClockwise) }
            }
        case .stopped, .off:
            Button { Task { await model.start() } } label: {
                Label { Text("開始") } icon: { Icon.menuImage(.play) }
            }
        case .requiresApproval:
            Button("ログイン項目を開く…") { BundledServer.openLoginItems() }
            Button { Task { await model.stop() } } label: {
                Label { Text("登録をやめる") } icon: { Icon.menuImage(.stop) }
            }
        case .legacy, .broken:
            // 案内（detail）だけ。メニューからは動かさない
            EmptyView()
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
