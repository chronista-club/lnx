import Foundation
import Observation
import UnisonClient

/// 常時接続の番人。つなぐ、名乗りと心拍を映す、切れたら間を置いてつなぎ直す。
/// iOS では背面に回ると接続は切れる — 「常時」の実際の意味は
/// 「前面にいる間は常時、戻ったら即つなぎ直す」（design 01）
@MainActor
@Observable
final class LinkSupervisor {
    private(set) var state: LinkState = .idle {
        didSet { LinkLog.note("state: \(state)") }
    }
    private(set) var heartbeat: Heartbeat?
    private(set) var servers: [RemoteServer] = []
    private(set) var target: LinkTarget?
    /// 一覧から選んだサーバ。選ぶと画面が切り替わる
    var selection: RemoteServer?

    private let transport: any LnxTransport
    private let pins: any PinStore
    private let backoff: BackoffPolicy
    /// 心拍が最初に届いたあと、この間なにも来なければ死んだとみなす
    private let heartbeatTimeout: Duration
    private var runner: Task<Void, Never>?
    /// 接続の世代。止める・解除・切り替えのたびに進め、古い世代のタスクには状態を書かせない。
    /// cancel と応答が競うと、遅れて戻った古い世代が connected を書き戻しうる
    /// （club-unison 2.2 までは待ちが cancel に応じず、なおさら起きた。deep レビュー P3-2）
    private var epoch = 0
    private var heartbeatCount = 0

    init(
        transport: any LnxTransport,
        pins: any PinStore,
        backoff: BackoffPolicy = BackoffPolicy(),
        heartbeatTimeout: Duration = .seconds(5)
    ) {
        self.transport = transport
        self.pins = pins
        self.backoff = backoff
        self.heartbeatTimeout = heartbeatTimeout
    }

    func start(target: LinkTarget) {
        LinkLog.note("start: \(target.displayName)")
        halt()
        self.target = target
        switch LinkTrust.decide(for: target, pins: pins) {
        case .needsPairing(let name):
            LinkLog.note("target: \(target.displayName) はペアリングが要る（\(name ?? "名前なし")）")
            heartbeat = nil
            state = .needsPairing(serverName: name)
        case .connect(let trust):
            LinkLog.note("target: \(target.displayName) へつなぐ（\(trust == .skipVerify ? "skipVerify" : "pinned")）")
            let epoch = epoch
            runner = Task { [weak self] in
                await self?.loop(target: target, trust: trust, epoch: epoch)
            }
        }
    }

    /// QR を読み終えた。今の先の QR なら pin を残してつなぎ直す。
    /// 名前が違う・今の先の名前が分からないときは受け取らない（pin を引けず、成功したように見えて固まるので）
    @discardableResult
    func paired(_ code: PairingCode) -> Bool {
        guard let target, case .host(_, _, let name?) = target, name == code.serverName else {
            LinkLog.note("paired: \(code.serverName) は今の先（\(target?.displayName ?? "なし")）の QR ではない")
            return false
        }
        LinkLog.note("paired: \(code.serverName)（証明書 \(code.certificate.count) バイト）")
        pins.save(code.certificate, for: code.serverName)
        start(target: target)
        return true
    }

    /// ペアリングをやめて、今の先へつなぎ直す（pin が残っていればそれで。無ければ needsPairing に戻るだけ）
    func cancelPairing() {
        if let target { start(target: target) }
    }

    /// ペアリング画面から戻れるか（今の先の pin が残っている）
    var canCancelPairing: Bool {
        guard case .host(_, _, let name?) = target else { return false }
        return pins.certificate(for: name) != nil
    }

    /// ペアリングを解除できるか（今の先が LAN のサーバ）
    var canUnpair: Bool {
        if case .host(_, _, _?) = target { return true }
        return false
    }

    /// ペアリングを解除する。pin を消して接続を畳み、ペアリング画面へ（LAN の先だけ）
    func unpair() {
        guard case .host(_, _, let name?) = target else { return }
        LinkLog.note("unpair: \(name) の pin を消す")
        pins.remove(for: name)
        halt()
        heartbeat = nil
        selection = nil
        state = .needsPairing(serverName: name)
    }

    /// ペアリングをやり直す（サーバの証明書が変わって pin が合わないとき）。LAN の先だけ
    func requestPairing() {
        guard case .host(_, _, let name) = target else { return }
        halt()
        heartbeat = nil
        state = .needsPairing(serverName: name)
    }

    /// つなぎ直しの待ちを飛ばして、今すぐつなぎにいく（前面に戻ったとき。design 01「戻ったら即つなぎ直す」）。
    /// 待っている（reconnecting）か、止まっている（idle）ときだけ
    func reconnectNow() {
        guard let target else { return }
        switch state {
        case .reconnecting, .idle:
            LinkLog.note("reconnectNow: \(target.displayName)")
            start(target: target)
        case .connecting, .connected, .needsPairing:
            break
        }
    }

    func stop() {
        halt()
        state = .idle
        heartbeat = nil
    }

    /// 今の世代を終わらせる（走っているタスクは以後、状態を書かない）。前の世代の心拍は残さない
    private func halt() {
        epoch += 1
        runner?.cancel()
        runner = nil
        heartbeat = nil
    }

    private func isCurrent(_ epoch: Int) -> Bool {
        epoch == self.epoch && !Task.isCancelled
    }

    private func loop(target: LinkTarget, trust: TrustPolicy, epoch: Int) async {
        var attempt = 0
        while isCurrent(epoch) {
            attempt += 1
            state = .connecting(attempt: attempt)
            do {
                let session = try await transport.connect(to: target, trust: trust)
                guard isCurrent(epoch) else {
                    await session.close()
                    break
                }
                let welcome: Welcome
                do {
                    welcome = try await session.hello(Hello(client: AppInfo.name, clientVersion: AppInfo.version))
                } catch {
                    await session.close()
                    throw error
                }
                guard isCurrent(epoch) else {
                    await session.close()
                    break
                }
                attempt = 0
                heartbeatCount = 0
                state = .connected(welcome)
                await run(session, epoch: epoch)
                if isCurrent(epoch) { heartbeat = nil }
            } catch is CancellationError {
                break
            } catch {
                LinkLog.note("connect failed: \(target.displayName) \(error)")
            }
            guard isCurrent(epoch) else { break }
            let shown = Swift.max(attempt, 1)
            let delay = backoff.delay(attempt: shown)
            state = .reconnecting(attempt: shown, delay: delay)
            do {
                try await Task.sleep(for: delay)
            } catch {
                break
            }
        }
    }

    /// 開いた窓を見張る。心拍・一覧・切断・無音のどれかが終わったら畳む。
    /// 子タスクは nonisolated にして、状態の更新だけ MainActor のメソッドへ渡す
    /// （`@MainActor` 付きの閉包を addTask に渡すと Swift 6 の isolation checker が解けない）
    private func run(_ session: any LnxSession, epoch: Int) async {
        let timeout = heartbeatTimeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await beat in await session.heartbeats() {
                    guard let self else { return }
                    await self.record(beat, epoch: epoch)
                }
            }
            group.addTask { [weak self] in
                if let list = try? await session.listServers() {
                    await self?.update(servers: list, epoch: epoch)
                }
                for await servers in await session.registryChanges() {
                    await self?.update(servers: servers, epoch: epoch)
                }
            }
            group.addTask {
                await session.waitUntilDisconnected()
            }
            group.addTask { [weak self] in
                // 無音の見張り。最初の心拍が来てから数え始める
                while !Task.isCancelled {
                    guard let self else { return }
                    let before = await self.heartbeatCount
                    do { try await Task.sleep(for: timeout) } catch { return }
                    if before > 0, await self.heartbeatCount == before { return }
                }
            }
            await group.next()
            group.cancelAll()
        }
        await session.close()
    }

    private func record(_ beat: Heartbeat, epoch: Int) {
        guard epoch == self.epoch else { return }
        heartbeat = beat
        heartbeatCount += 1
    }

    private func update(servers: [RemoteServer], epoch: Int) {
        guard epoch == self.epoch else { return }
        self.servers = servers
    }
}
