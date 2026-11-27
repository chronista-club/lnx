import SwiftUI

/// lnx creare — LNX への入り口。開いたら、すぐ場につながる。
@main
struct LnxCreareApp: App {
    #if os(macOS)
    /// メニューバーの lnx サーバ（同梱の lnx-server を SMAppService で常駐させ、Gear の状態とログを見張る）
    @State private var server: ServerMenuModel
    @State private var gearLogs = GearLogViewModel()

    init() {
        let probe = GearProbe()
        let server = ServerMenuModel(residency: BundledServer(), gearProbe: probe)
        server.startWatching()
        _server = State(initialValue: server)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task { await probe.close() }
        }
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
        Window("lnx — Gear ステータス", id: LnxWindow.gearStatus) {
            GearStatusWindow(model: server)
        }
        .defaultSize(width: 920, height: 480)
        Window("lnx — Gear & Desk", id: LnxWindow.gearDesk) {
            GearDeskView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 920, height: 620)
        Window("lnx — ログとトレース", id: LnxWindow.gearLog) {
            GearLogWindow(server: server, vm: gearLogs)
        }
        .defaultSize(width: 980, height: 520)
        MenuBarExtra {
            LnxMenu(model: server, logs: gearLogs)
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
