import Foundation
import Testing
@testable import LnxCreare

/// 接続の足跡 — 他の lane（サーバ側のログ）と突き合わせられるよう、行に時刻を付ける
@Suite("LinkLog")
struct LinkLogTests {
    @Test("行の頭に、その機械の時刻をミリ秒まで付ける")
    func stampsTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 7, minute: 19, second: 31, nanosecond: 238_000_000)))
        let line = LinkLog.line("resolving: lnx-mac", at: date, timeZone: calendar.timeZone)
        #expect(line == "[link] 07:19:31.238 resolving: lnx-mac\n")
    }
}
