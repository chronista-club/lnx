import Foundation

/// 常時接続の今
enum LinkState: Equatable, Sendable {
    case idle
    case connecting(attempt: Int)
    case connected(Welcome)
    case reconnecting(attempt: Int, delay: Duration)
    /// LAN のサーバとまだペアリングしていない（証明書を知らない）。QR を読むまでつながない
    case needsPairing(serverName: String?)
}
