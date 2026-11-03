import Foundation
import Testing
import UnisonClient
@testable import LnxCreare

/// 常時接続の番人。つなぐ、心拍を映す、切れたら間を置いてつなぎ直す
@Suite("LinkSupervisor")
@MainActor
struct LinkSupervisorTests {
    private func makeSupervisor(_ transport: FakeTransport, pins: any PinStore = MemoryPinStore()) -> LinkSupervisor {
        LinkSupervisor(
            transport: transport,
            pins: pins,
            backoff: BackoffPolicy(base: .milliseconds(10), max: .milliseconds(20))
        )
    }

    @Test("つながると connected になり、名乗りと心拍が映る")
    func connectsAndShowsHeartbeat() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }

        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        let session = await transport.latestSession()
        await session.emit(Heartbeat(seq: 1, uptimeMs: 1000))
        try await eventually { supervisor.heartbeat == Heartbeat(seq: 1, uptimeMs: 1000) }
    }

    @Test("切れたら reconnecting を経て、つなぎ直す")
    func reconnectsAfterDrop() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }

        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        let first = await transport.latestSession()
        await first.drop()
        try await eventually { await transport.connectCount == 2 }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
    }

    @Test("つながらない間は attempt を数えながら待つ")
    func countsAttemptsWhileUnreachable() async throws {
        let transport = FakeTransport(failures: 2)
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }

        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(await transport.connectCount == 3)
    }

    @Test("一覧が届くと servers に入る")
    func receivesServerList() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }

        try await eventually { supervisor.servers == FakeSession.servers }
        let session = await transport.latestSession()
        let more = FakeSession.servers + [RemoteServer(id: "x", name: "X", kind: "test", host: "h", port: 1)]
        await session.emitRegistry(more)
        try await eventually { supervisor.servers == more }
    }

    @Test("同じ機械へは検証を飛ばしてつなぐ")
    func localDaemonSkipsVerify() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }

        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(await transport.trusts == [.skipVerify])
    }

    @Test("ペアリング済みの LAN サーバへは pin してつなぐ")
    func pairedHostIsPinned() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        pins.save(Data([9, 9]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }

        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(await transport.trusts == [.pinned(Data([9, 9]))])
    }

    @Test("ペアリングしていない LAN サーバにはつながず、needsPairing で待つ")
    func unpairedHostWaitsForPairing() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }

        try await eventually { supervisor.state == .needsPairing(serverName: "lnx-mac") }
        try await Task.sleep(for: .milliseconds(60))
        #expect(await transport.connectCount == 0)
    }

    @Test("ペアリングし終えたら、同じ先へつなぎにいく")
    func connectsAfterPairing() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .needsPairing(serverName: "lnx-mac") }

        supervisor.paired(PairingCode(serverName: "lnx-mac", certificate: Data([7])))
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(pins.certificate(for: "lnx-mac") == Data([7]))
        #expect(await transport.trusts == [.pinned(Data([7]))])
    }

    @Test("ペアリングし直すと、LAN の先は needsPairing に戻る")
    func requestPairingReturnsToPairing() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }

        supervisor.requestPairing()
        #expect(supervisor.state == .needsPairing(serverName: "lnx-mac"))
    }

    @Test("同じ機械の先ではペアリングし直さない")
    func requestPairingIgnoresLocalDaemon() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }

        supervisor.requestPairing()
        #expect(supervisor.state == .connected(FakeSession.welcome))
    }

    @Test("stop で idle に戻り、以後つなぎ直さない")
    func stopGoesIdle() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        supervisor.stop()
        #expect(supervisor.state == .idle)
        try await Task.sleep(for: .milliseconds(60))
        #expect(await transport.connectCount == 1)
    }
}

// MARK: - 偽の transport（実 QUIC の代わり）

actor FakeTransport: LnxTransport {
    private(set) var connectCount = 0
    /// connect ごとに渡された信頼方針
    private(set) var trusts: [TrustPolicy] = []
    private var failuresLeft: Int
    private var sessions: [FakeSession] = []

    init(failures: Int = 0) {
        failuresLeft = failures
    }

    func connect(to target: LinkTarget, trust: TrustPolicy) async throws -> any LnxSession {
        connectCount += 1
        trusts.append(trust)
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw FakeError.unreachable
        }
        let session = FakeSession()
        sessions.append(session)
        return session
    }

    func latestSession() -> FakeSession {
        sessions.last!
    }

    enum FakeError: Error { case unreachable }
}

actor FakeSession: LnxSession {
    static let welcome = Welcome(serverName: "fake", serverVersion: "0.0.0", serverTimeMs: 42)
    static let servers = [RemoteServer(id: "ladyland.field", name: "Ladyland Field", kind: "field", host: "h", port: 7879)]

    private let heartbeatStream: AsyncStream<Heartbeat>
    private let heartbeatSink: AsyncStream<Heartbeat>.Continuation
    private let registryStream: AsyncStream<[RemoteServer]>
    private let registrySink: AsyncStream<[RemoteServer]>.Continuation
    private let dropStream: AsyncStream<Void>
    private let dropSink: AsyncStream<Void>.Continuation
    private var dropped = false

    init() {
        (heartbeatStream, heartbeatSink) = AsyncStream<Heartbeat>.makeStream()
        (registryStream, registrySink) = AsyncStream<[RemoteServer]>.makeStream()
        (dropStream, dropSink) = AsyncStream<Void>.makeStream()
    }

    func hello(_ hello: Hello) async throws -> Welcome { Self.welcome }
    func listServers() async throws -> [RemoteServer] { Self.servers }
    func heartbeats() -> AsyncStream<Heartbeat> { heartbeatStream }
    func registryChanges() -> AsyncStream<[RemoteServer]> { registryStream }

    /// 切れるまで待つ。AsyncStream なので cancel で抜けられる
    func waitUntilDisconnected() async {
        for await _ in dropStream { return }
    }

    func close() {
        drop()
    }

    // テストから: 心拍 / 一覧 / 切断
    func emit(_ heartbeat: Heartbeat) { heartbeatSink.yield(heartbeat) }
    func emitRegistry(_ servers: [RemoteServer]) { registrySink.yield(servers) }
    func drop() {
        guard !dropped else { return }
        dropped = true
        heartbeatSink.finish()
        registrySink.finish()
        dropSink.yield(())
        dropSink.finish()
    }
}

/// 条件が満たされるまで待つ（上限つき）
@MainActor
func eventually(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("条件が \(timeout) 以内に満たされなかった")
}
