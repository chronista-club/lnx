import Foundation
import Testing
@testable import LnxCreare

/// 名前の見せ方（spec 01「名前と表記」、起票 mem_1ChKHcAuXn7Yfo9mtEoTpm）。画面に出す名前は小文字の lnx。
/// 大文字の「LNX」単独は Linux と読まれやすいので出さない。識別子（LnxXxx、_lnx._udp、lnx://、bundle id）は変えない
@Suite("名前の見せ方")
struct NamingTests {
    static let phases: [ServerPhase] = [
        .running(pid: 1), .stopped(lastExit: "1"), .off, .requiresApproval,
        .legacy(running: true), .legacy(running: false), .broken,
        .portTaken(PortListener(pid: 2, command: "lnx-server"), registration: .notRegistered),
    ]

    @Test("メニューの 1 行目は「lnx サーバ — 」で始まる", arguments: phases)
    func menuTitle(_ phase: ServerPhase) {
        #expect(phase.title.hasPrefix("lnx サーバ — "))
    }

    @Test("メニューバーのアイコンの読み上げ名も lnx")
    func menuBarName() {
        #expect(LnxMenuBarIcon.accessibilityName(running: true) == "lnx サーバ（動いています）")
        #expect(LnxMenuBarIcon.accessibilityName(running: false) == "lnx サーバ（止まっています）")
    }

    /// apps/ios（このファイルの 2 つ上）
    static let appsIOS = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// 大文字の LNX が単独で出ているところ（前後が英字・数字・_ なら識別子の一部なので除く）
    static func standaloneLNX(in text: String) -> Bool {
        text.range(of: #"(?<![A-Za-z0-9_])LNX(?![A-Za-z0-9_])"#, options: .regularExpression) != nil
    }

    /// Swift のソースで、大文字の LNX 単独を含む行の番号（1 始まり）。コメントの行（// と ///）は画面に出ないので見ない。
    /// 文字列リテラルを抜き出さずに行全体を見る（補間の中の文字列や複数行の文字列も拾える。識別子は Lnx・LNX_ で外れる）
    static func violations(inSwiftSource source: String) -> [Int] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            return !isComment && standaloneLNX(in: String(line)) ? index + 1 : nil
        }
    }

    @Test("画面に出る文字列（アプリのソースのコメント以外）に大文字の LNX 単独が無い")
    func sourceStrings() throws {
        let root = Self.appsIOS.appending(path: "LnxCreare")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        var found: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            found += Self.violations(inSwiftSource: source).map { "\(file.lastPathComponent):\($0)" }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test("権限の説明文（Info.plist と project.yml の INFOPLIST_KEY_）に大文字の LNX 単独が無い")
    func usageDescriptions() throws {
        let plist = try String(contentsOf: Self.appsIOS.appending(path: "LnxCreare/Info.plist"), encoding: .utf8)
        let strings = plist.matches(of: #/<string>([^<]*)</string>/#).map { String($0.output.1) }
        let project = try String(contentsOf: Self.appsIOS.appending(path: "project.yml"), encoding: .utf8)
        let keys = project.split(separator: "\n").filter { $0.contains("INFOPLIST_KEY_") }.map(String.init)
        let found = (strings + keys).filter(Self.standaloneLNX(in:))
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test("識別子は判定から外れる（型名・Bonjour の種類・URL・bundle id、大文字でも前後に英数字や _ が付くもの）")
    func identifiersAreNotFlagged() {
        #expect(!Self.standaloneLNX(in: "LnxDefaults"))
        #expect(!Self.standaloneLNX(in: "_lnx._udp"))
        #expect(!Self.standaloneLNX(in: "lnx://pair?v=1"))
        #expect(!Self.standaloneLNX(in: "club.chronista.lnx.creare"))
        // 前後を見る条件を試す（ただの "LNX" の検索ならここで引っかかる）
        #expect(!Self.standaloneLNX(in: "LNX_SERVER_ADDR"))
        #expect(!Self.standaloneLNX(in: "LNXKit"))
        #expect(!Self.standaloneLNX(in: "MyLNX"))
        #expect(!Self.standaloneLNX(in: "LNX2"))
        #expect(Self.standaloneLNX(in: "LNX を探しています"))
        #expect(Self.standaloneLNX(in: "この Mac の LNX（手元用）"))
    }

    @Test("ソースの走査は、補間の中の文字列と複数行の文字列も拾い、コメントは見ない")
    func scansWholeLines() {
        let source = #"""
            Text("接続先: \(name ?? "LNX")")
            let message = """
                LNX を探しています
                """
            // LNX の画面（コメントは画面に出ない）
            /// LNX サーバの見出し
            let defaults = LnxDefaults.port
            let env = "LNX_SERVER_ADDR"
            """#
        #expect(Self.violations(inSwiftSource: source) == [1, 3])
    }
}
