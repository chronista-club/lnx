import SwiftUI

/// 窓の枠。接続の今と選んだサーバで中身が切り替わる
struct RootView: View {
    @State private var supervisor: LinkSupervisor
    @State private var finder = LnxFinder()
    @Environment(\.scenePhase) private var scenePhase
    /// pin の置き場はアプリ全体で 1 つ（窓が複数あっても cache を共有する）
    private let pins: any PinStore = CachedPinStore.shared

    init() {
        _supervisor = State(initialValue: LinkSupervisor(transport: UnisonLnxTransport(), pins: CachedPinStore.shared))
    }

    var body: some View {
        ZStack {
            Backdrop()
            switch ScreenRoute.resolve(state: supervisor.state, selection: supervisor.selection) {
            case .connecting:
                ConnectingView(state: supervisor.state, target: supervisor.target) {
                    supervisor.requestPairing()
                }
            case .pairing(let name):
                PairingView(
                    serverName: name,
                    onPaired: { supervisor.paired($0) },
                    onCancel: supervisor.canCancelPairing ? { supervisor.cancelPairing() } : nil
                )
                // 待つサーバが変わったら作り直す（スキャナの覚えている中身やエラー文を持ち越さない）
                .id(name)
            case .lnxHome:
                LnxHomeView(supervisor: supervisor)
            case .remote(let server):
                RemoteServerView(server: server) { supervisor.selection = nil }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: ScreenRoute.resolve(state: supervisor.state, selection: supervisor.selection))
        .task { await connectWhenFound() }
        // 前面に戻ったら、つなぎ直しの待ちを飛ばして今すぐ（design 01「戻ったら即つなぎ直す」）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { supervisor.reconnectNow() }
        }
        .onDisappear {
            supervisor.stop()
            finder.stop()
        }
    }

    /// 見つかった先へつなぐ。見つかるまでは探し続ける
    private func connectWhenFound() async {
        finder.start()
        while !Task.isCancelled {
            // LAN の先へのつなぎ直しが続けて失敗していたら、アドレスを解き直してもらう（経路が変わった恐れ）
            if supervisor.needsFreshAddress { finder.refresh() }
            if let target = finder.preferred(pins: pins, current: supervisor.target) {
                if supervisor.target != target {
                    supervisor.start(target: target)
                } else if supervisor.state == .idle {
                    // 窓が消えて戻った（onDisappear で stop 済み）。先は同じでも、つなぎ直す
                    supervisor.reconnectNow()
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

#Preview {
    RootView()
}
