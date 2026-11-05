#if os(macOS)
import Foundation
import Observation

/// 同梱した lnx-server の出し入れ。実物は BundledServer（SMAppService + launchctl）、テストは偽物
@MainActor
protocol ServerResidency {
    func currentRegistration() -> Registration
    /// server:install（tasks/_lib/agent.rb）の plist が ~/Library/LaunchAgents にあるか
    func legacyInstalled() -> Bool
    func register() throws
    func unregister() async throws
    /// launchd に載っていなければ nil
    func job() async -> LaunchdJob?
    /// 12730 / 12731 で待ち受けているプロセス（常駐自身も含む）
    func listeners() async -> [PortListener]
}

/// メニューの操作が断られた理由
enum ServerMenuError: LocalizedError {
    case legacyInstalled
    case portTaken(PortListener)

    var errorDescription: String? {
        switch self {
        case .legacyInstalled: "server:install の常駐が入っています。先に mise run server:uninstall で外してください"
        case .portTaken(let holder):
            "\(holder.command)（pid \(holder.pid)）が待ち受け（\(LnxDefaults.port) / \(LnxDefaults.localPort)）を握っています。止めてから開始してください（端末の mise run server:run なら Ctrl-C）"
        }
    }
}

/// メニューバーの LNX サーバ。開始 = 登録、停止 = 登録の解除（ログイン時にも立ち上がらない）、
/// 再起動 = 解除 → 前のプロセスが消えるのを待つ → 登録（midistage の Residency と同じ形、mem_1Cfuxqjxy6HUi7p7ByQRY4）
@MainActor
@Observable
final class ServerMenuModel {
    /// 再起動で前のプロセスが消えるのを見る回数と間（最大 5 秒）。SMAppService の unregister は reap を待たないので、
    /// 待たずに登録すると新しいサーバが port を取り合う。消えなければ登録して launchd に任せる
    static let reapChecks = 20
    static let reapInterval: Duration = .milliseconds(250)

    private(set) var phase: ServerPhase = .off
    private(set) var lastError: String?
    private(set) var busy = false

    @ObservationIgnored private let residency: any ServerResidency
    @ObservationIgnored private let pause: @MainActor (Duration) async -> Void
    @ObservationIgnored private var watching: Task<Void, Never>?

    init(residency: any ServerResidency, pause: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.residency = residency
        self.pause = pause
    }

    /// アイコンが今を表すよう、見張り続ける（launchctl print を数秒おきに）
    func startWatching(every interval: Duration = .seconds(2)) {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        var job = await residency.job()
        let registration = residency.currentRegistration()
        // 常駐が走っているあいだは、待ち受けを握っているのは常駐自身。見張りでは lsof を回さない
        let running = registration == .enabled && job?.isRunning == true
        let listeners = running ? [] : await residency.listeners()
        // 開始の直後は、launchd を読んだあとに常駐が bind していることがある。外のものに見えたら読み直して確かめる
        if PortListener.foreign(in: listeners, job: job) != nil {
            job = await residency.job()
        }
        phase = ServerPhase.resolve(
            registration: registration, job: job, legacyInstalled: residency.legacyInstalled(), listeners: listeners
        )
    }

    func start() async {
        await perform {
            try self.refuseLegacy()
            try await self.refusePortTaken()
            if self.residency.currentRegistration() == .enabled {
                try await self.reRegister()
            } else {
                try self.residency.register()
            }
        }
    }

    func stop() async {
        await perform { try await self.residency.unregister() }
    }

    func restart() async {
        await perform {
            try self.refuseLegacy()
            try await self.refusePortTaken()
            try await self.reRegister()
        }
    }

    /// 同じラベルを二つ載せようとしない（server:install の常駐が先に居る）
    private func refuseLegacy() throws {
        if residency.legacyInstalled() { throw ServerMenuError.legacyInstalled }
    }

    /// launchd の外のプロセスが待ち受けを握っているうちは登録しない（KeepAlive で落ち続ける。2026-11-05 の事故）
    private func refusePortTaken() async throws {
        let job = await residency.job()
        if let holder = PortListener.foreign(in: await residency.listeners(), job: job) {
            throw ServerMenuError.portTaken(holder)
        }
    }

    /// 実行ファイルを入れ直したときも、これで新しい同梱版に入れ替える（SDK のヘッダは、実行ファイルを変えたら解除してから登録し直すよう求めている）
    private func reRegister() async throws {
        // 未登録なら解除は失敗する（kSMErrorJobNotFound）。登録へ進む
        try? await residency.unregister()
        for check in 1...Self.reapChecks {
            guard let job = await residency.job(), job.isRunning else { break }
            if check < Self.reapChecks { await pause(Self.reapInterval) }
        }
        try residency.register()
    }

    private func perform(_ action: @MainActor () async throws -> Void) async {
        busy = true
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
        busy = false
    }
}
#endif
