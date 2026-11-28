import Foundation
import UnisonClient

public final class Client: Sendable {
    private let connection: Connection
    private let channel: StreamChannel<GearChannel>

    private init(connection: Connection, channel: StreamChannel<GearChannel>) {
        self.connection = connection
        self.channel = channel
    }

    public static var defaultEndpointURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(
            "Library/Application Support/tech.anycreative.lnx-server/endpoint.json"
        )
    }

    /// 常駐サービスの版違いを検出しても停止・上書きしない。
    public static func connect(
        endpointURL: URL = defaultEndpointURL,
        clientID: String,
        displayName: String,
        nativeMIDI: Bool = true,
        initialEnabledProfiles: [String] = []
    ) async throws -> (Client, Snapshot) {
        let endpoint = try JSONDecoder().decode(ServiceEndpoint.self, from: Data(contentsOf: endpointURL))
        guard endpoint.protocolVersion == 1 else {
            throw ProtocolFailure(code: "incompatible_protocol", message: "service protocol version differs")
        }
        let connection = try await UnisonClient.connect(
            to: .localDaemon(port: endpoint.port),
            trust: .pinned(Data(endpoint.certificateDER))
        )
        do {
            let channel = try await deadline(
                seconds: 3,
                operation: { try await connection.openChannel(GearChannel()) },
                onTimeout: { await connection.disconnect() }
            )
            let client = Client(connection: connection, channel: channel)
            let snapshot = try await client.request(
                HelloRequest(
                    protocolVersion: 1,
                    clientID: clientID,
                    displayName: displayName,
                    authToken: endpoint.authToken,
                    nativeMIDI: nativeMIDI,
                    initialEnabledProfiles: initialEnabledProfiles
                )
            )
            guard snapshot.serverEpoch == endpoint.serverEpoch && snapshot.protocolVersion == 1 else {
                await client.close()
                throw ProtocolFailure(code: "epoch_changed", message: "service changed during connection")
            }
            return (client, snapshot)
        } catch {
            await connection.disconnect()
            throw error
        }
    }

    public var events: AsyncStream<Event> { channel.events }

    public func setEnabled(
        gearID: String, enabled: Bool, expectedRevision: UInt64, takeover: Bool = false
    ) async throws -> Snapshot {
        try await request(
            SetEnabledRequest(
                gearID: gearID, enabled: enabled, expectedRevision: expectedRevision, takeover: takeover
            )
        )
    }

    /// アプリの入力停止・発音整理・出力キュー停止が完了してから呼ぶ。
    public func quiesced(gearID: String, leaseToken: String) async throws -> Snapshot {
        try await request(QuiescedRequest(gearID: gearID, leaseToken: leaseToken))
    }

    /// SysEx は物理ドライバの completion まで待つ（最大 128 KiB の SysEx を考慮して 10 秒）。
    public func sendMIDI(
        gearID: String, leaseToken: String, portName: String, bytes: [UInt8]
    ) async throws -> Snapshot {
        try await request(
            SendMIDIRequest(gearID: gearID, leaseToken: leaseToken, portName: portName, bytes: bytes),
            seconds: 10
        )
    }

    /// Gear の表示（名前・値・色）を更新する。
    public func present(
        gearID: String, leaseToken: String, controls: [ControlPresentation]
    ) async throws -> Snapshot {
        try await request(
            PresentRequest(gearID: gearID, leaseToken: leaseToken, controls: controls)
        )
    }

    /// 自分の setup（Roto 本体の保存枠 0〜63 等）を登録する。空で取り消し。
    public func setGearSetups(gearID: String, setups: [Int]) async throws -> Snapshot {
        try await request(SetGearSetupsRequest(gearID: gearID, setups: setups))
    }

    /// lease を持つ間、自分の setup の中で切り替える。
    public func selectSetup(gearID: String, leaseToken: String, setup: Int) async throws -> Snapshot {
        try await request(SelectSetupRequest(gearID: gearID, leaseToken: leaseToken, setup: setup))
    }

    /// setup の中身をまるごと書く。
    public func applyGearSetup(
        gearID: String, leaseToken: String, setup: Int, content: SetupContent
    ) async throws -> Snapshot {
        try await request(
            ApplyGearSetupRequest(gearID: gearID, leaseToken: leaseToken, setup: setup, content: content)
        )
    }

    public func snapshot() async throws -> Snapshot {
        try await request(SnapshotRequest())
    }

    public func close() async {
        await channel.close()
        await connection.disconnect()
    }

    private func request<R: UnisonRequest & Sendable>(_ request: R, seconds: Int = 3) async throws -> Snapshot
    where R.Response == Reply {
        let reply = try await Self.deadline(
            seconds: seconds,
            operation: { try await self.channel.request(request) },
            onTimeout: { await self.close() }
        )
        return try reply.value()
    }

    private static func deadline<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T,
        onTimeout: @escaping @Sendable () async -> Void
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                await onTimeout()
                throw ProtocolFailure(code: "timeout", message: "service response timed out")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

private struct GearChannel: StreamChannelMeta {
    static let name = "gear"
    typealias Event = LnxClient.Event
}

private struct HelloRequest: UnisonRequest, Sendable {
    static let method = "Hello"
    typealias Response = Reply
    var protocolVersion: UInt32
    var clientID: String
    var displayName: String
    var authToken: String
    var nativeMIDI: Bool
    var initialEnabledProfiles: [String]
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", clientID = "client_id"
        case displayName = "display_name", authToken = "auth_token"
        case nativeMIDI = "native_midi", initialEnabledProfiles = "initial_enabled_profiles"
    }
}

private struct SetEnabledRequest: UnisonRequest, Sendable {
    static let method = "SetEnabled"
    typealias Response = Reply
    var gearID: String
    var enabled: Bool
    var expectedRevision: UInt64
    var takeover: Bool
    enum CodingKeys: String, CodingKey {
        case gearID = "gear_id", enabled, expectedRevision = "expected_revision", takeover
    }
}

private struct QuiescedRequest: UnisonRequest, Sendable {
    static let method = "Quiesced"
    typealias Response = Reply
    var gearID: String
    var leaseToken: String
    enum CodingKeys: String, CodingKey { case gearID = "gear_id", leaseToken = "lease_token" }
}

private struct SnapshotRequest: UnisonRequest, Sendable {
    static let method = "Snapshot"
    typealias Response = Reply
}

private struct SendMIDIRequest: UnisonRequest, Sendable {
    static let method = "SendMidi"
    typealias Response = Reply
    var gearID: String
    var leaseToken: String
    var portName: String
    var bytes: [UInt8]
    enum CodingKeys: String, CodingKey {
        case gearID = "gear_id", leaseToken = "lease_token", portName = "port_name", bytes
    }
}

private struct PresentRequest: UnisonRequest, Sendable {
    static let method = "Present"
    typealias Response = Reply
    var gearID: String
    var leaseToken: String
    var controls: [ControlPresentation]
    enum CodingKeys: String, CodingKey {
        case gearID = "gear_id", leaseToken = "lease_token", controls
    }
}

private struct SetGearSetupsRequest: UnisonRequest, Sendable {
    static let method = "SetGearSetups"
    typealias Response = Reply
    var gearID: String
    var setups: [Int]
    enum CodingKeys: String, CodingKey { case gearID = "gear_id", setups }
}

private struct SelectSetupRequest: UnisonRequest, Sendable {
    static let method = "SelectSetup"
    typealias Response = Reply
    var gearID: String
    var leaseToken: String
    var setup: Int
    enum CodingKeys: String, CodingKey { case gearID = "gear_id", leaseToken = "lease_token", setup }
}

private struct ApplyGearSetupRequest: UnisonRequest, Sendable {
    static let method = "ApplyGearSetup"
    typealias Response = Reply
    var gearID: String
    var leaseToken: String
    var setup: Int
    var content: SetupContent
    enum CodingKeys: String, CodingKey {
        case gearID = "gear_id", leaseToken = "lease_token", setup, content
    }
}
