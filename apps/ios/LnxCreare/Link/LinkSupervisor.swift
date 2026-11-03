import Foundation
import Observation

/// 常時接続の番人。つなぐ、名乗りと心拍を映す、切れたら間を置いてつなぎ直す。
/// iOS では背面に回ると接続は切れる — 「常時」の実際の意味は
/// 「前面にいる間は常時、戻ったら即つなぎ直す」（design 01）
@MainActor
@Observable
final class LinkSupervisor {
    private(set) var state: LinkState = .idle
    private(set) var heartbeat: Heartbeat?
    private(set) var servers: [RemoteServer] = []
    private(set) var target: LinkTarget?
    /// 一覧から選んだサーバ。選ぶと画面が切り替わる
    var selection: RemoteServer?

    private let transport: any LnxTransport
    private let backoff: BackoffPolicy
    /// 心拍が最初に届いたあと、この間なにも来なければ死んだとみなす
    private let heartbeatTimeout: Duration
    private var runner: Task<Void, Never>?
    private var heartbeatCount = 0

    init(
        transport: any LnxTransport,
        backoff: BackoffPolicy = BackoffPolicy(),
        heartbeatTimeout: Duration = .seconds(5)
    ) {
        self.transport = transport
        self.backoff = backoff
        self.heartbeatTimeout = heartbeatTimeout
    }

    func start(target: LinkTarget) {
        runner?.cancel()
        self.target = target
        runner = Task { [weak self] in
            await self?.loop(target: target)
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        state = .idle
        heartbeat = nil
    }

    private func loop(target: LinkTarget) async {
        var attempt = 0
        while !Task.isCancelled {
            attempt += 1
            state = .connecting(attempt: attempt)
            do {
                let session = try await transport.connect(to: target)
                let welcome: Welcome
                do {
                    welcome = try await session.hello(Hello(client: AppInfo.name, clientVersion: AppInfo.version))
                } catch {
                    await session.close()
                    throw error
                }
                attempt = 0
                heartbeatCount = 0
                state = .connected(welcome)
                await run(session)
                heartbeat = nil
            } catch is CancellationError {
                break
            } catch {
                // つながらない。間を置いてもう一度
            }
            if Task.isCancelled { break }
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
    private func run(_ session: any LnxSession) async {
        let timeout = heartbeatTimeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await beat in await session.heartbeats() {
                    guard let self else { return }
                    await self.record(beat)
                }
            }
            group.addTask { [weak self] in
                if let list = try? await session.listServers() {
                    await self?.update(servers: list)
                }
                for await servers in await session.registryChanges() {
                    await self?.update(servers: servers)
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

    private func record(_ beat: Heartbeat) {
        heartbeat = beat
        heartbeatCount += 1
    }

    private func update(servers: [RemoteServer]) {
        self.servers = servers
    }
}
