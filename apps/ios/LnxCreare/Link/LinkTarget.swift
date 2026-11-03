import Foundation

/// つなぐ先
enum LinkTarget: Equatable, Hashable, Sendable {
    /// 同じ機械の loopback（開発中の Mac、シミュレータ）
    case localDaemon(port: UInt16)
    /// LAN 上の LNX サーバ（Bonjour で見つけた、または手で入れた）。name は Bonjour のインスタンス名で、pin を引くキー
    case host(String, port: UInt16, name: String? = nil)

    var displayName: String {
        switch self {
        case .localDaemon(let port): "localhost:\(port)"
        case .host(let host, let port, _): "\(host):\(port)"
        }
    }
}

/// LNX サーバの既定ポート（crates/lnx-server の DEFAULT_PORT と対）
enum LnxDefaults {
    static let port: UInt16 = 12730
    /// 手元用（ループバックだけ）。ペアリング URL を取る（crates/lnx-server の DEFAULT_LOCAL_ADDR と対）
    static let localPort: UInt16 = 12731
    static let bonjourType = "_lnx._udp"
}
