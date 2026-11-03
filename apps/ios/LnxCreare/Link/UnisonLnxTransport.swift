import Foundation
import UnisonClient

/// 実物 — club-unison の Swift client で QUIC をつなぐ
struct UnisonLnxTransport: LnxTransport {
    /// dev は自己署名の dev cert なので検証を飛ばす。pin は次の区切り（design 01）
    var trust: TrustPolicy = .skipVerify

    func connect(to target: LinkTarget) async throws -> any LnxSession {
        let trust = self.trust
        // ⚠️ 全部タイムアウトで包む — 応答が消えると await が永遠に固まる（Ladyland の実例）
        let connection = try await withTimeout(seconds: 5) {
            try await UnisonClient.connect(to: target.unisonEndpoint, trust: trust)
        }
        do {
            let session = try await withTimeout(seconds: 3) {
                try await connection.openChannel(SessionChannel())
            }
            let registry = try await withTimeout(seconds: 3) {
                try await connection.openChannel(RegistryChannel())
            }
            return UnisonLnxSession(connection: connection, session: session, registry: registry)
        } catch {
            await connection.disconnect()
            throw error
        }
    }
}

extension LinkTarget {
    var unisonEndpoint: Endpoint {
        switch self {
        case .localDaemon(let port): .localDaemon(port: port)
        case .host(let host, let port): .host(host, port: port)
        }
    }
}

final class UnisonLnxSession: LnxSession, @unchecked Sendable {
    private let connection: Connection
    private let session: StreamChannel<SessionChannel>
    private let registry: StreamChannel<RegistryChannel>

    init(connection: Connection, session: StreamChannel<SessionChannel>, registry: StreamChannel<RegistryChannel>) {
        self.connection = connection
        self.session = session
        self.registry = registry
    }

    func hello(_ hello: Hello) async throws -> Welcome {
        let session = self.session
        return try await withTimeout(seconds: 3) { try await session.request(hello) }
    }

    func listServers() async throws -> [RemoteServer] {
        let registry = self.registry
        return try await withTimeout(seconds: 3) { try await registry.request(ListServers()) }.servers
    }

    func heartbeats() async -> AsyncStream<Heartbeat> {
        session.events
    }

    func registryChanges() async -> AsyncStream<[RemoteServer]> {
        let source = registry.events
        return AsyncStream { continuation in
            let task = Task {
                for await change in source {
                    continuation.yield(change.servers)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func waitUntilDisconnected() async {
        for await event in connection.connectionEvents {
            if case .disconnected = event { return }
        }
    }

    func close() async {
        await connection.disconnect()
    }
}

/// 期限つき await（超えたら LinkTimeout）
func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw LinkTimeout(seconds: seconds)
        }
        guard let first = try await group.next() else { throw LinkTimeout(seconds: seconds) }
        group.cancelAll()
        return first
    }
}

struct LinkTimeout: Error, CustomStringConvertible {
    let seconds: Double
    var description: String { "\(seconds) 秒待っても応答がない" }
}
