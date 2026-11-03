import Foundation
import UnisonClient

/// つなぐ先ごとの信頼の決め方（design 01）。
/// 同じ機械（localhost）は dev cert のまま検証を飛ばす。LAN のサーバはペアリングした証明書に pin し、
/// ペアリングしていなければつながない
enum LinkTrust: Equatable, Sendable {
    case connect(TrustPolicy)
    case needsPairing(serverName: String?)

    static func decide(for target: LinkTarget, pins: any PinStore) -> LinkTrust {
        switch target {
        case .localDaemon:
            return .connect(.skipVerify)
        case .host(_, _, let name):
            guard let name, let certificate = pins.certificate(for: name) else {
                return .needsPairing(serverName: name)
            }
            return .connect(.pinned(certificate))
        }
    }
}
