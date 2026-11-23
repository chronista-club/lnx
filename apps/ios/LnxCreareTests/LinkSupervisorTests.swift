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

    @Test("ペアリングし直すと pin が新しい証明書に替わり、それでつなぐ")
    func repairingReplacesPin() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }

        supervisor.requestPairing()
        supervisor.paired(PairingCode(serverName: "lnx-mac", certificate: Data([2])))
        try await eventually { await transport.connectCount == 2 }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(pins.certificate(for: "lnx-mac") == Data([2]))
        #expect(await transport.trusts == [.pinned(Data([1])), .pinned(Data([2]))])
    }

    @Test("ペアリングをやめると、前の pin でつなぎ直す")
    func cancelPairingReconnectsWithOldPin() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }

        supervisor.requestPairing()
        #expect(supervisor.canCancelPairing)
        supervisor.cancelPairing()
        try await eventually { await transport.connectCount == 2 }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(await transport.trusts == [.pinned(Data([1])), .pinned(Data([1]))])
    }

    @Test("pin が無ければペアリング画面から戻れない")
    func cannotCancelWithoutPin() async throws {
        let supervisor = makeSupervisor(FakeTransport())
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        #expect(supervisor.state == .needsPairing(serverName: "lnx-mac"))
        #expect(!supervisor.canCancelPairing)
    }

    @Test("つながっている最中に未ペアリングの先へ替えると、前の接続を止めて needsPairing")
    func switchingToUnpairedHostStopsOldLink() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        let session = await transport.latestSession()
        await session.emit(Heartbeat(seq: 1, uptimeMs: 1000))
        try await eventually { supervisor.heartbeat != nil }

        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-pi"))
        #expect(supervisor.state == .needsPairing(serverName: "lnx-pi"))
        #expect(supervisor.heartbeat == nil)
        try await Task.sleep(for: .milliseconds(60))
        #expect(supervisor.state == .needsPairing(serverName: "lnx-pi"))
        #expect(await transport.connectCount == 1)
    }

    @Test("ペアリングを解除すると pin を消し、接続を畳んで needsPairing")
    func unpairForgetsPin() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }

        supervisor.unpair()
        #expect(pins.certificate(for: "lnx-mac") == nil)
        #expect(supervisor.state == .needsPairing(serverName: "lnx-mac"))
        #expect(!supervisor.canCancelPairing)
        try await Task.sleep(for: .milliseconds(60))
        #expect(await transport.connectCount == 1)
    }

    @Test("解除してからペアリングし直すと、新しい pin でつなぎ直す。選んでいたサーバは外れる")
    func unpairThenPair() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        supervisor.selection = FakeSession.servers[0]

        supervisor.unpair()
        #expect(supervisor.selection == nil)
        supervisor.paired(PairingCode(serverName: "lnx-mac", certificate: Data([2])))
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(await transport.trusts == [.pinned(Data([1])), .pinned(Data([2]))])
    }

    @Test("同じ機械の先ではペアリングを解除できない")
    func unpairIgnoresLocalDaemon() async throws {
        let supervisor = makeSupervisor(FakeTransport())
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(!supervisor.canUnpair)
        supervisor.unpair()
        #expect(supervisor.state == .connected(FakeSession.welcome))
    }

    @Test("名乗りの最中に解除しても、遅れて戻った応答で connected に戻らない")
    func lateHelloDoesNotOverwriteUnpair() async throws {
        let latch = Latch()
        let transport = FakeTransport(helloLatch: latch)
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }
        try await eventually { await transport.connectCount == 1 }

        supervisor.unpair()
        latch.open(0)
        try await Task.sleep(for: .milliseconds(80))
        #expect(supervisor.state == .needsPairing(serverName: "lnx-mac"))
    }

    @Test("名乗りの最中に stop しても、遅れて戻った応答で connected に戻らない")
    func lateHelloDoesNotOverwriteStop() async throws {
        let latch = Latch()
        let transport = FakeTransport(helloLatch: latch)
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        try await eventually { await transport.connectCount == 1 }

        supervisor.stop()
        latch.open(0)
        try await Task.sleep(for: .milliseconds(80))
        #expect(supervisor.state == .idle)
    }

    @Test("今の先と名前が違う QR は受け取らず、pin も残さない")
    func pairedRejectsOtherServer() async throws {
        let transport = FakeTransport()
        let pins = MemoryPinStore()
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }

        #expect(!supervisor.paired(PairingCode(serverName: "lnx-pi", certificate: Data([7]))))
        #expect(pins.certificate(for: "lnx-pi") == nil)
        #expect(supervisor.state == .needsPairing(serverName: "lnx-mac"))
        #expect(await transport.connectCount == 0)
    }

    @Test("名前の分からない先には QR を受け取らない（受け取っても pin を引けず固まる）")
    func pairedRejectsNamelessTarget() async throws {
        let pins = MemoryPinStore()
        let supervisor = makeSupervisor(FakeTransport(), pins: pins)
        supervisor.start(target: .host("192.168.0.2", port: 12730))
        defer { supervisor.stop() }

        #expect(!supervisor.paired(PairingCode(serverName: "lnx-mac", certificate: Data([7]))))
        #expect(pins.certificate(for: "lnx-mac") == nil)
    }

    @Test("つなぎ直しを待っている間に reconnectNow すると、待たずにつなぎにいく（前面に戻ったとき）")
    func reconnectNowSkipsBackoff() async throws {
        let transport = FakeTransport(failures: 1)
        let supervisor = LinkSupervisor(
            transport: transport,
            pins: MemoryPinStore(),
            backoff: BackoffPolicy(base: .seconds(30), max: .seconds(30))
        )
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }
        try await eventually {
            if case .reconnecting = supervisor.state { return true }
            return false
        }

        supervisor.reconnectNow()
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        #expect(await transport.connectCount == 2)
    }

    @Test("つながっている・ペアリング待ちのときの reconnectNow は何もしない")
    func reconnectNowIgnoredWhenNotWaiting() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }

        supervisor.reconnectNow()
        try await Task.sleep(for: .milliseconds(60))
        #expect(await transport.connectCount == 1)
    }

    @Test("先を切り替えたら、前のサーバの心拍は残さない")
    func switchingTargetClearsHeartbeat() async throws {
        let transport = FakeTransport()
        let supervisor = makeSupervisor(transport)
        supervisor.start(target: .localDaemon(port: 1))
        defer { supervisor.stop() }
        try await eventually { supervisor.state == .connected(FakeSession.welcome) }
        await transport.latestSession().emit(Heartbeat(seq: 9, uptimeMs: 9000))
        try await eventually { supervisor.heartbeat != nil }

        supervisor.start(target: .localDaemon(port: 2))
        #expect(supervisor.heartbeat == nil)
    }

    @Test("LAN の先へのつなぎ直しが 2 回続けて失敗したら、アドレスを解き直してほしいと言う")
    func needsFreshAddressAfterRepeatedFailures() async throws {
        let transport = FakeTransport(failures: 100)
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let supervisor = makeSupervisor(transport, pins: pins)
        supervisor.start(target: .host("192.168.234.1", port: 12730, name: "lnx-mac"))
        defer { supervisor.stop() }

        #expect(!supervisor.needsFreshAddress)
        try await eventually { supervisor.needsFreshAddress }
        #expect(await transport.connectCount >= 2)
    }

    @Test("同じ機械の先や、つながっているときは解き直しを求めない")
    func noFreshAddressForLocalOrConnected() async throws {
        let failing = makeSupervisor(FakeTransport(failures: 100))
        failing.start(target: .localDaemon(port: 1))
        defer { failing.stop() }
        try await eventually {
            if case .reconnecting(let attempt, _) = failing.state { return attempt >= 3 }
            return false
        }
        #expect(!failing.needsFreshAddress)

        let ok = makeSupervisor(FakeTransport())
        ok.start(target: .localDaemon(port: 1))
        defer { ok.stop() }
        try await eventually { ok.state == .connected(FakeSession.welcome) }
        #expect(!ok.needsFreshAddress)
    }

    @Test("LAN の先でも、つながっているとき・1 回目の失敗では解き直しを求めない")
    func noFreshAddressBeforeSecondFailure() async throws {
        let pins = MemoryPinStore()
        pins.save(Data([1]), for: "lnx-mac")
        let once = makeSupervisor(FakeTransport(failures: 1), pins: pins)
        once.start(target: .host("192.168.0.2", port: 12730, name: "lnx-mac"))
        defer { once.stop() }
        try await eventually {
            if case .reconnecting(1, _) = once.state { return true }
            return false
        }
        #expect(!once.needsFreshAddress)
        try await eventually { once.state == .connected(FakeSession.welcome) }
        #expect(!once.needsFreshAddress)
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

    /// 名乗り（hello）の応答を止めておく栓。開けるまで hello は戻らない（cancel にも応じない）
    private let helloLatch: Latch?

    init(failures: Int = 0, helloLatch: Latch? = nil) {
        failuresLeft = failures
        self.helloLatch = helloLatch
    }

    func connect(to target: LinkTarget, trust: TrustPolicy) async throws -> any LnxSession {
        connectCount += 1
        trusts.append(trust)
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw FakeError.unreachable
        }
        let session = FakeSession(helloLatch: helloLatch)
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

    private let helloLatch: Latch?

    init(helloLatch: Latch? = nil) {
        self.helloLatch = helloLatch
        (heartbeatStream, heartbeatSink) = AsyncStream<Heartbeat>.makeStream()
        (registryStream, registrySink) = AsyncStream<[RemoteServer]>.makeStream()
        (dropStream, dropSink) = AsyncStream<Void>.makeStream()
    }

    func hello(_ hello: Hello) async throws -> Welcome {
        if let helloLatch { _ = await helloLatch.wait() }
        return Self.welcome
    }
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
