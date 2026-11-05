import SwiftUI

/// lnx creare — LNX への入り口。開いたら、すぐ場につながる。
@main
struct LnxCreareApp: App {
    #if os(macOS)
    /// メニューバーの LNX サーバ（同梱の lnx-server を SMAppService で常駐させる）
    @State private var server: ServerMenuModel

    init() {
        let server = ServerMenuModel(residency: BundledServer())
        server.startWatching()
        _server = State(initialValue: server)
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        // 窓は 1 つ（メニューバーの「窓を開く」で前に出す。WindowGroup だと開くたびに接続が増える）
        Window(AppInfo.name, id: LnxWindow.main) {
            RootView()
        }
        .defaultSize(width: 900, height: 720)
        Window("iPad をペアリング", id: LnxWindow.pairing) {
            PairingWindow()
        }
        .windowResizability(.contentSize)
        MenuBarExtra {
            LnxMenu(model: server)
        } label: {
            LnxMenuBarIcon(running: server.phase.isRunning)
        }
        .menuBarExtraStyle(.menu)
        #else
        WindowGroup {
            RootView()
        }
        #endif
    }
}
