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
    private(set) var gearRows: [GearRow] = []
    private(set) var gearSummary = GearSummary(present: 0, releasingStuck: 0, errors: 0)
    private(set) var gearServiceVersion: String?
    private(set) var tracing = GearTrace.isOn()

    @ObservationIgnored private let residency: any ServerResidency
    @ObservationIgnored private let gearProbe: any GearProbing
    @ObservationIgnored private let pause: @MainActor (Duration) async -> Void
    @ObservationIgnored private var watching: Task<Void, Never>?

    init(
        residency: any ServerResidency,
        gearProbe: any GearProbing = NoopGearProbe(),
        pause: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.residency = residency
        self.gearProbe = gearProbe
        self.pause = pause
    }

    var gearSummaryLine: String? {
        guard phase.isRunning else { return nil }
        var parts = ["Gear: \(gearSummary.present) 台接続"]
        if gearSummary.errors > 0 {
            parts.append("エラー \(gearSummary.errors) 件")
        }
        if gearSummary.releasingStuck > 0 {
            parts.append("引き継ぎ待ち \(gearSummary.releasingStuck) 件")
        }
        return parts.joined(separator: " / ")
    }

    func startTrace() {
        do {
            try GearTrace.start()
            tracing = GearTrace.isOn()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopTrace() {
        do {
            try GearTrace.stop()
            tracing = GearTrace.isOn()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func closeProbe() async {
        await gearProbe.close()
    }

    /// アイコンが今を表すよう、見張り続ける（launchctl print を数秒おきに。常駐が走っていないときは lsof も）
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
        job = await rereadIfForeign(listeners, job: job)
        phase = ServerPhase.resolve(
            registration: registration, job: job, legacyInstalled: residency.legacyInstalled(), listeners: listeners
        )
        tracing = GearTrace.isOn()
        if phase.isRunning {
            let probed = await gearProbe.probe()
            gearRows = gearStatusRows(probed.gears)
            gearSummary = probed.summary
            gearServiceVersion = probed.serviceVersion
        } else {
            await gearProbe.close()
            gearRows = []
            gearSummary = GearSummary(present: 0, releasingStuck: 0, errors: 0)
            gearServiceVersion = nil
        }
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
        let listeners = await residency.listeners()
        let job = await rereadIfForeign(listeners, job: await residency.job())
        if let holder = PortListener.foreign(in: listeners, job: job) {
            throw ServerMenuError.portTaken(holder)
        }
    }

    /// 外のものに見えたら launchd を読み直す。launchd を読んだあとに常駐が bind していることがある
    /// （開始の直後、KeepAlive がちょうど起こし直したとき）。読み直せば常駐自身だと分かる
    private func rereadIfForeign(_ listeners: [PortListener], job: LaunchdJob?) async -> LaunchdJob? {
        PortListener.foreign(in: listeners, job: job) == nil ? job : await residency.job()
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
