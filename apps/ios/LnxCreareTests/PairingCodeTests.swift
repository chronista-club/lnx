import Foundation
import Testing
@testable import LnxCreare

/// ペアリングの QR — `lnx://pair?v=1&name=<サーバ名>&cert=<leaf DER の base64url、padding なし>`
@Suite("PairingCode")
struct PairingCodeTests {
    /// padding が要る長さ（5 バイト → base64 で 8 文字、うち "=" 1 つ）と、"-" "_" が出るバイトを混ぜる
    let der = Data([0x30, 0xfb, 0xff, 0x3e, 0x01])

    @Test("名前と証明書を読む（base64url、padding なし）")
    func parses() throws {
        let code = try PairingCode(parsing: "lnx://pair?v=1&name=lnx-mac&cert=MPv_PgE")
        #expect(code == PairingCode(serverName: "lnx-mac", certificate: der))
    }

    @Test("名前は percent-encoding を解く")
    func decodesName() throws {
        let code = try PairingCode(parsing: "lnx://pair?v=1&name=lnx%20mac%20(2)&cert=MPv_PgE")
        #expect(code.serverName == "lnx mac (2)")
    }

    @Test("前後の空白や改行は無視する（貼り付け）")
    func trimsWhitespace() throws {
        let code = try PairingCode(parsing: "  lnx://pair?v=1&name=lnx-mac&cert=MPv_PgE\n")
        #expect(code.serverName == "lnx-mac")
    }

    @Test("書いた文字列を読み戻せる")
    func roundTrip() throws {
        let code = PairingCode(serverName: "lnx mac", certificate: der)
        #expect(try PairingCode(parsing: code.string) == code)
    }

    @Test("ペアリングの QR でないものは読まない", arguments: [
        "https://example.com/pair?v=1&name=a&cert=MPv_PgE",  // scheme 違い
        "lnx://open?v=1&name=a&cert=MPv_PgE",               // host 違い
        "lnx://pair?v=2&name=a&cert=MPv_PgE",               // 知らない版
        "lnx://pair?name=a&cert=MPv_PgE",                   // 版なし
        "lnx://pair?v=1&cert=MPv_PgE",                      // 名前なし
        "lnx://pair?v=1&name=&cert=MPv_PgE",                // 名前が空
        "lnx://pair?v=1&name=a",                            // 証明書なし
        "lnx://pair?v=1&name=a&cert=",                      // 証明書が空
        "lnx://pair?v=1&name=a&cert=%%%",                   // base64url でない
        "ただの文字",
    ])
    func rejects(_ text: String) {
        #expect(throws: PairingCode.ParseError.self) { try PairingCode(parsing: text) }
    }

    @Test("待っているサーバの QR だけ受け取る")
    func acceptsOnlyExpectedServer() throws {
        let text = "lnx://pair?v=1&name=lnx-mac&cert=MPv_PgE"
        #expect(try PairingCode.accept(text, for: "lnx-mac").serverName == "lnx-mac")
        #expect(try PairingCode.accept(text, for: nil).serverName == "lnx-mac")
        #expect(throws: PairingCode.ParseError.otherServer("lnx-mac")) { try PairingCode.accept(text, for: "lnx-pi") }
    }
}
