import Foundation

/// 画面の振り分け。つながるまでは接続画面、つながれば LNX の画面、選べば相手の画面
enum ScreenRoute: Equatable {
    case connecting
    case lnxHome
    case remote(RemoteServer)
    case pairing(serverName: String?)

    static func resolve(state: LinkState, selection: RemoteServer?) -> ScreenRoute {
        if case .needsPairing(let name) = state { return .pairing(serverName: name) }
        guard case .connected = state else { return .connecting }
        if let selection { return .remote(selection) }
        return .lnxHome
    }
}
