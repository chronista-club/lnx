import Testing
@testable import LnxCreare

/// 画面の振り分け — つながるまでは接続画面、つながれば LNX の画面、選べば相手の画面
@Suite("ScreenRoute")
struct ScreenRouteTests {
    let welcome = Welcome(serverName: "lnx-mac", serverVersion: "0.1.0", serverTimeMs: 0)
    let field = RemoteServer(id: "ladyland.field", name: "Ladyland Field", kind: "field", host: "h", port: 7879)

    @Test("未接続なら接続画面")
    func connecting() {
        #expect(ScreenRoute.resolve(state: .idle, selection: nil) == .connecting)
        #expect(ScreenRoute.resolve(state: .connecting(attempt: 1), selection: nil) == .connecting)
    }

    @Test("接続中で選択なしなら LNX の画面")
    func home() {
        #expect(ScreenRoute.resolve(state: .connected(welcome), selection: nil) == .lnxHome)
    }

    @Test("サーバを選ぶとその画面へ切り替わる")
    func remote() {
        #expect(ScreenRoute.resolve(state: .connected(welcome), selection: field) == .remote(field))
    }

    @Test("再接続中は選択があっても接続画面に戻る")
    func reconnecting() {
        let state = LinkState.reconnecting(attempt: 2, delay: .seconds(1))
        #expect(ScreenRoute.resolve(state: state, selection: field) == .connecting)
    }
}
