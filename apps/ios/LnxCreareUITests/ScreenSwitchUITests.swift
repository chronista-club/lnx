import XCTest

/// 一覧から選ぶと画面が切り替わり、戻れる（LNX サーバが居るときだけ。居なければ skip）
final class ScreenSwitchUITests: XCTestCase {
    @MainActor
    func test一覧から選ぶと相手の画面に切り替わり戻れる() throws {
        let app = XCUIApplication()
        app.launch()

        let cell = app.buttons["server.ladyland.field"]
        guard cell.waitForExistence(timeout: 15) else {
            throw XCTSkip("LNX サーバが居ない（mise run server:run で立ててから走らせる）")
        }
        cell.tap()

        let title = app.staticTexts["remote.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "相手の画面に切り替わらない")
        XCTAssertEqual(title.label, "Ladyland Field")

        app.buttons["remote.back"].tap()
        XCTAssertTrue(app.staticTexts["home.heartbeat"].waitForExistence(timeout: 5), "LNX の画面に戻らない")
    }
}
