import Foundation

/// 接続まわりの足跡。stderr に出す（stdout はパイプ先だとバッファされて届かない。
/// 実機は `xcrun devicectl device process launch --console` で読める）
enum LinkLog {
    static func note(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data("[link] \(message())\n".utf8))
    }
}
