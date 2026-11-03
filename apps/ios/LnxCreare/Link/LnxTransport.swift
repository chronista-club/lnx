import Foundation
import UnisonClient

/// 接続の作り方。実物は Unison（QUIC）、テストでは偽物
protocol LnxTransport: Sendable {
    func connect(to target: LinkTarget, trust: TrustPolicy) async throws -> any LnxSession
}

/// 開いた窓 1 枚ぶん。session と registry の 2 channel を束ねる
protocol LnxSession: Sendable {
    func hello(_ hello: Hello) async throws -> Welcome
    func listServers() async throws -> [RemoteServer]
    func heartbeats() async -> AsyncStream<Heartbeat>
    func registryChanges() async -> AsyncStream<[RemoteServer]>
    /// 接続が切れるまで待つ（切れていれば即戻る）
    func waitUntilDisconnected() async
    func close() async
}
