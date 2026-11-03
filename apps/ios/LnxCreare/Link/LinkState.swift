import Foundation

/// 常時接続の今
enum LinkState: Equatable, Sendable {
    case idle
    case connecting(attempt: Int)
    case connected(Welcome)
    case reconnecting(attempt: Int, delay: Duration)
}
