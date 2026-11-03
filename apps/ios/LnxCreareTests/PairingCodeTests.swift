import Foundation
import Testing
@testable import LnxCreare

/// ペアリングの QR — `lnx://pair?v=1&name=<サーバ名>&cert=<leaf DER の base64url、padding なし>`
@Suite("PairingCode")
struct PairingCodeTests {
    /// 本物の自己署名証明書（P-256、CN=lnx-test）。base64url で "-" "_" を含み、padding が 1 つ要る長さ
    static let certText = "MIIBWjCCAQCgAwIBAgIUDRe21bvz95Oo8hy5k147AYSVB48wCgYIKoZIzj0EAwIwEzERMA8GA1UEAwwIbG54LXRlc3QwHhcNMjYxMTAzMjEzNTAxWhcNMzYxMDMxMjEzNTAxWjATMREwDwYDVQQDDAhsbngtdGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABEeHBHAVT2DsZhwU3YHbHwF3YjAl7cDm-HhW7_mU2Yk37R8QM0xKIcjqsA613RA1QwGpdMQPH2nXP4FRrw6d4BCjMjAwMB0GA1UdDgQWBBQqk7V8YzC9a9ahTakEc7oTO9VVRjAPBgNVHRMBAf8EBTADAQH_MAoGCCqGSM49BAMCA0gAMEUCIFm23Fmtt64Y0gz1d81C2eKMpey3IJWBS88U_FDcDMRIAiEAwFA3saZ6H24Jymwm4Xd2IwbcUj3GfmAlu5wOKNcMbHw"
    let der = Data(base64Encoded: certText.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "=")!
    let cert = Self.certText

    @Test("名前と証明書を読む（base64url、padding なし）")
    func parses() throws {
        let code = try PairingCode(parsing: "lnx://pair?v=1&name=lnx-mac&cert=\(cert)")
        #expect(code == PairingCode(serverName: "lnx-mac", certificate: der))
    }

    @Test("名前は percent-encoding を解く")
    func decodesName() throws {
        let code = try PairingCode(parsing: "lnx://pair?v=1&name=lnx%20mac%20(2)&cert=\(cert)")
        #expect(code.serverName == "lnx mac (2)")
    }

    @Test("前後の空白や改行は無視する（貼り付け）")
    func trimsWhitespace() throws {
        let code = try PairingCode(parsing: "  lnx://pair?v=1&name=lnx-mac&cert=\(cert)\n")
        #expect(code.serverName == "lnx-mac")
    }

    @Test("書いた文字列を読み戻せる")
    func roundTrip() throws {
        let code = PairingCode(serverName: "lnx mac", certificate: der)
        #expect(try PairingCode(parsing: code.string) == code)
    }

    @Test("ペアリングの QR でないものは読まない", arguments: [
        "https://example.com/pair?v=1&name=a&cert=\(certText)",  // scheme 違い
        "lnx://open?v=1&name=a&cert=\(certText)",               // host 違い
        "lnx://pair?v=2&name=a&cert=\(certText)",               // 知らない版
        "lnx://pair?name=a&cert=\(certText)",                   // 版なし
        "lnx://pair?v=1&cert=\(certText)",                      // 名前なし
        "lnx://pair?v=1&name=&cert=\(certText)",                // 名前が空
        "lnx://pair?v=1&name=a",                            // 証明書なし
        "lnx://pair?v=1&name=a&cert=",                      // 証明書が空
        "lnx://pair?v=1&name=a&cert=%%%",                   // base64url でない
        "lnx://pair?v=1&name=a&cert=MPv_PgE",               // base64url だが証明書でない
        "ただの文字",
    ])
    func rejects(_ text: String) {
        #expect(throws: PairingCode.ParseError.self) { try PairingCode(parsing: text) }
    }

    @Test("待っているサーバの QR だけ受け取る")
    func acceptsOnlyExpectedServer() throws {
        let text = "lnx://pair?v=1&name=lnx-mac&cert=\(cert)"
        #expect(try PairingCode.accept(text, for: "lnx-mac").serverName == "lnx-mac")
        #expect(try PairingCode.accept(text, for: nil).serverName == "lnx-mac")
        #expect(throws: PairingCode.ParseError.otherServer("lnx-mac")) { try PairingCode.accept(text, for: "lnx-pi") }
    }

    /// lnx-server（#28）が実際に出した URL（--name 'lnx test (2)'、2026-11-04）。サーバとの契約の見本
    @Test("lnx-server が出す URL を読める")
    func readsServerOutput() throws {
        let url = "lnx://pair?v=1&name=lnx%20test%20%282%29&cert=MIIBdzCCARygAwIBAgIUQrMGHBcYv-b04zIhRooJou38AEgwCgYIKoZIzj0EAwIwITEfMB0GA1UEAwwWcmNnZW4gc2VsZiBzaWduZWQgY2VydDAgFw03NTAxMDEwMDAwMDBaGA80MDk2MDEwMTAwMDAwMFowITEfMB0GA1UEAwwWcmNnZW4gc2VsZiBzaWduZWQgY2VydDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKbDF_vlWwCOAy5SnV7s_PKDIN71xytTfx_XSbVAimSZWpRzG-_p-4D663Tlr03RicSCmxQq__puMiMv8ixks3qjMDAuMCwGA1UdEQQlMCOCCWxvY2FsaG9zdIcQAAAAAAAAAAAAAAAAAAAAAYcEfwAAATAKBggqhkjOPQQDAgNJADBGAiEAwrL7KdIkc2psrGLfGyIEC9QqVRR9IDeTZ-IeulUNVRsCIQD_o_GA8nXxfBEVJx86tInHU2jdx767kWfg4qed6iPj_A"
        let code = try PairingCode(parsing: url)
        #expect(code.serverName == "lnx test (2)")
        #expect(code.certificate.count == 379)
    }
}
