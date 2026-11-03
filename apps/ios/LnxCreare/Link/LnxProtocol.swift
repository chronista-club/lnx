import Foundation
import UnisonClient

// LNX プロトコルの Swift 側の写し。wire の形は crates/lnx-server/schemas/lnx.kdl が正。
// KDL → Swift の codegen は club-unison の将来項目なので、当面は手書き。
// ここがズレるとサーバと話が通じない（snake_case は CodingKeys で合わせる）。

/// session channel — 名乗り（Hello / Welcome）と心拍（Heartbeat）
struct SessionChannel: StreamChannelMeta {
    static let name = "session"
    typealias Event = Heartbeat
}

/// 常駐の生存証明。1 秒に 1 回
struct Heartbeat: Decodable, Sendable, Equatable {
    var seq: Int
    var uptimeMs: Int

    enum CodingKeys: String, CodingKey {
        case seq
        case uptimeMs = "uptime_ms"
    }
}

/// 窓を開ける
struct Hello: UnisonRequest {
    static let method = "Hello"
    typealias Response = Welcome

    var client: String
    var clientVersion: String

    enum CodingKeys: String, CodingKey {
        case client
        case clientVersion = "client_version"
    }
}

/// サーバの名乗り
struct Welcome: Decodable, Sendable, Equatable {
    var serverName: String
    var serverVersion: String
    var serverTimeMs: Int

    enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case serverVersion = "server_version"
        case serverTimeMs = "server_time_ms"
    }
}

/// registry channel — 知っているサーバの一覧（List）と変化（RegistryChanged）
struct RegistryChannel: StreamChannelMeta {
    static let name = "registry"
    typealias Event = RegistryChanged
}

struct RegistryChanged: Decodable, Sendable, Equatable {
    var servers: [RemoteServer]
}

struct ListServers: UnisonRequest {
    static let method = "List"
    typealias Response = ServerList
}

struct ServerList: Decodable, Sendable, Equatable {
    var servers: [RemoteServer]
}

/// LNX が知っているサーバ 1 件。kind で画面を選ぶ
struct RemoteServer: Codable, Sendable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var host: String
    var port: UInt16

    /// 画面用の "host:port"。`Text("\(port)")` は数値を桁区切りしてしまう（7,879）ので文字列で組む
    var endpointLabel: String { "\(host):\(String(port))" }
}
