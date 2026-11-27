import Testing
@testable import LnxCreare

/// ホームの heartbeat の表記（mako の依頼 2026-11-24: 訳語の「心拍」より見慣れた「heartbeat」で）
@Suite("Heartbeat の表記")
@MainActor
struct HeartbeatTextTests {
    @Test("まだ届いていないとき")
    func waiting() {
        #expect(LnxHomeView.heartbeatText(nil) == "heartbeat を待っています")
    }

    @Test("番号と、サーバの起動からの経過")
    func beat() {
        #expect(LnxHomeView.heartbeatText(Heartbeat(seq: 31, uptimeMs: 65_400)) == "heartbeat #31 · 起動から 1 分 5 秒")
    }

    @Test("画面の文言に「心拍」を使わない")
    func noShinpaku() {
        #expect(!LnxHomeView.heartbeatText(nil).contains("心拍"))
        #expect(!LnxHomeView.heartbeatText(Heartbeat(seq: 1, uptimeMs: 0)).contains("心拍"))
    }
}
