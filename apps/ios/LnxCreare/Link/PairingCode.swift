import Foundation

/// ペアリングの QR の中身。LNX サーバが起動時に出し、アプリが読んで pin する（design 01）。
/// 形: `lnx://pair?v=1&name=<サーバ名>&cert=<leaf 証明書 DER の base64url、padding なし>`。
/// `name` は Bonjour のインスタンス名と同じで、pin を引くキーになる
struct PairingCode: Equatable, Sendable {
    var serverName: String
    var certificate: Data

    enum ParseError: Error, Equatable {
        case notPairingCode
        case unsupportedVersion
        case missingName
        case invalidCertificate
        /// 待っていたのと別のサーバの QR
        case otherServer(String)
    }

    init(serverName: String, certificate: Data) {
        self.serverName = serverName
        self.certificate = certificate
    }

    init(parsing text: String) throws(ParseError) {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "lnx", components.host == "pair"
        else { throw .notPairingCode }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("v") == "1" else { throw .unsupportedVersion }
        guard let name = value("name"), !name.isEmpty else { throw .missingName }
        guard let cert = value("cert").flatMap(Self.decodeBase64URL), !cert.isEmpty else { throw .invalidCertificate }
        self.init(serverName: name, certificate: cert)
    }

    /// 読んだ上で、待っているサーバのものか確かめる（expected が nil なら誰でもよい）
    static func accept(_ text: String, for expected: String?) throws(ParseError) -> PairingCode {
        let code = try PairingCode(parsing: text)
        if let expected, code.serverName != expected { throw .otherServer(code.serverName) }
        return code
    }

    var string: String {
        var components = URLComponents()
        components.scheme = "lnx"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "name", value: serverName),
            URLQueryItem(name: "cert", value: Self.encodeBase64URL(certificate)),
        ]
        return components.string ?? ""
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
