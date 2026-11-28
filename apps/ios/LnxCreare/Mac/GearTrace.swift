#if os(macOS)
import Foundation

// MIDI トレース（開発用）のオン／オフ。lnx-server は <state_dir>/trace の有無を毎秒見て切り替える。
enum GearTrace {
    static var stateDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/tech.anycreative.lnx-server")
    }
    static var flagURL: URL { stateDir.appending(path: "trace") }

    static func isOn() -> Bool {
        FileManager.default.fileExists(atPath: flagURL.path)
    }

    static func start() throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try Data().write(to: flagURL)
    }

    static func stop() throws {
        do {
            try FileManager.default.removeItem(at: flagURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // 既に消えていればそのまま成功とする
        }
    }
}
#endif
