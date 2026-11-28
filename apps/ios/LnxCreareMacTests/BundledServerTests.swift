import Foundation
import Testing
@testable import LnxCreare

/// ビルドした .app に lnx-server と LaunchAgent の plist が入っているか（scripts/embed-lnx-server.sh の仕事）。
/// テストの host は LnxCreare.app なので、Bundle.main がそれ
@Suite("同梱の lnx-server")
struct BundledServerTests {
    let app = Bundle.main.bundleURL

    @Test("plist は Contents/Library/LaunchAgents にあり、ラベルは server:install と同じ")
    func plist() throws {
        let url = app.appending(path: "Contents/Library/LaunchAgents/\(BundledServer.plistName)")
        let data = try Data(contentsOf: url)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "tech.anycreative.lnx-server")
        #expect(plist["BundleProgram"] as? String == "Contents/MacOS/lnx-server")
        // launchd は ~ を展開しないので、ログの置き場はサーバが --log-file で展開する
        #expect(plist["ProgramArguments"] as? [String] == ["lnx-server", "--log-file", "~/Library/Logs/lnx-server.log"])
        #expect(plist["RunAtLoad"] as? Bool == true)
        // crash だけ立ち上がり直す。SIGTERM で畳んだ（exit 0）ときは起こし直さない
        let keepAlive = try #require(plist["KeepAlive"] as? [String: Any])
        #expect(keepAlive["SuccessfulExit"] as? Bool == false)
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == ["tech.anycreative.lnx.creare"])
    }

    @Test("lnx-server の実行ファイルが Contents/MacOS にあり、走る")
    func executable() throws {
        let url = app.appending(path: "Contents/MacOS/lnx-server")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        let process = Process()
        process.executableURL = url
        process.arguments = ["--help"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(out.contains("--local-addr"))
        // plist が渡す --log-file を受ける版が入っている（無い版だと clap が断り、KeepAlive で立て直し続ける）
        #expect(out.contains("--log-file"))
    }
}
