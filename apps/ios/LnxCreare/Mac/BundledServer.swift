#if os(macOS)
import Foundation
import ServiceManagement

/// .app に同梱した lnx-server（scripts/embed-lnx-server.sh が入れる）を SMAppService の LaunchAgent として出し入れする。
/// 登録・解除は人の操作でだけ呼ぶ（起動しただけで勝手に register しない）
struct BundledServer: ServerResidency {
    /// server:install（tasks/_lib/agent.rb の DEFAULT_LABEL）と同じ。launchd は同じラベルを二つ載せない
    nonisolated static let label = "club.chronista.lnx-server"
    nonisolated static let plistName = "\(label).plist"

    nonisolated private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    /// lnx-server のログ（server:install と同じ場所）
    nonisolated static var logURL: URL { home.appending(path: "Library/Logs/lnx-server.log") }
    /// server:install が置く plist
    nonisolated static var legacyPlistURL: URL { home.appending(path: "Library/LaunchAgents/\(plistName)") }

    /// 常駐は登録した .app の中の lnx-server を、次の起動（落ちたとき・ログイン時）で使う。
    /// build-mac の .app は mac:run / mac:test のたびに中身が変わり、worktree を消すと行き先も無くなるので、
    /// 常駐は mac:install で Applications に入れた .app から登録する
    nonisolated static func isInstalled(_ app: URL) -> Bool {
        app.deletingLastPathComponent().lastPathComponent == "Applications"
    }

    private var service: SMAppService { .agent(plistName: Self.plistName) }

    func currentRegistration() -> Registration {
        let plist = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchAgents/\(Self.plistName)")
        return Registration(service.status, plistInBundle: FileManager.default.fileExists(atPath: plist.path))
    }

    func legacyInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.legacyPlistURL.path)
    }

    func register() throws {
        try service.register()
    }

    /// 走っていれば launchd が止める（SIGTERM → lnx-server は goodbye を出して畳む）。reap は待たない
    func unregister() async throws {
        try await service.unregister()
    }

    func job() async -> LaunchdJob? {
        await Launchctl.print("gui/\(getuid())/\(Self.label)").map(LaunchdJob.parse)
    }

    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// launchctl を読むだけに使う（出し入れは SMAppService）
enum Launchctl {
    /// `launchctl print <service>` の出力。載っていなければ nil
    static func print(_ service: String) async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print", service]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }
}
#endif
