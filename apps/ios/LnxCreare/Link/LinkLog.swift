import Foundation

/// 接続まわりの足跡。stderr に出す（stdout はパイプ先だとバッファされて届かない。
/// 実機は `xcrun devicectl device process launch --console` で読める）。
/// 行の頭に時刻（その機械の時刻、ミリ秒まで）を付ける。サーバ側のログと突き合わせるため
enum LinkLog {
    static func note(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data(line(message(), at: Date(), timeZone: .current).utf8))
    }

    static func line(_ message: String, at date: Date, timeZone: TimeZone) -> String {
        "[link] \(date.formatted(stamp(timeZone))) \(message)\n"
    }

    private static func stamp(_ timeZone: TimeZone) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
