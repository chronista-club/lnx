import SwiftUI

/// 窓の枠。接続の今と選んだサーバで中身が切り替わる
struct RootView: View {
    @State private var supervisor = LinkSupervisor(transport: UnisonLnxTransport(), pins: KeychainPinStore())
    @State private var finder = LnxFinder()
    private let pins = KeychainPinStore()

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
            case .lnxHome:
                LnxHomeView(supervisor: supervisor)
            case .remote(let server):
                RemoteServerView(server: server) { supervisor.selection = nil }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: ScreenRoute.resolve(state: supervisor.state, selection: supervisor.selection))
        .task { await connectWhenFound() }
        .onDisappear {
            supervisor.stop()
            finder.stop()
        }
    }

    /// 見つかった先へつなぐ。見つかるまでは探し続ける
    private func connectWhenFound() async {
        finder.start()
        while !Task.isCancelled {
            if let target = finder.preferred(pins: pins), supervisor.target != target {
                supervisor.start(target: target)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

#Preview {
    RootView()
}
