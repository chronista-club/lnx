import Testing
@testable import LnxCreare

/// 看板の値を固定する。テストターゲットがアプリモジュールに届いていることの確認でもある。
@Suite("AppInfo")
struct AppInfoTests {
    @Test("表示名は Bevy 版 lnx-creare のウィンドウタイトルと同じ")
    func displayName() {
        #expect(AppInfo.name == "lnx creare")
    }

    @Test("タグラインは README の結びと同じ")
    func tagline() {
        #expect(AppInfo.tagline == "Build the wave, Feel the experience")
    }
}
