import Testing
@testable import LnxCreare

/// 守り: launchd の外のプロセスが 12730 / 12731 を握っているうちは、「開始」「再起動」を出さずに案内する。
/// 握られたまま常駐させると、同梱の lnx-server は bind に失敗して KeepAlive で 10 秒おきに落ち続ける
/// （2026-11-05 06:46〜07:28 の事故。design 01「やってはいけない」）
@Suite("待ち受けの守り")
struct PortGuardTests {
    let runningJob = LaunchdJob(state: "running", pid: 10, lastExit: "(never exited)")
    let loopingJob = LaunchdJob(state: "spawn scheduled", pid: nil, lastExit: "1")
    let terminal = PortListener(pid: 68111, command: "lnx-server")

    @Test("lsof -F pcn から、待ち受けているプロセスだけを拾う（相手の決まったソケットはクライアント）")
    func parsesListeners() {
        let out = "p8349\nclnx-server\nn[::1]:12731\nn*:12730\np99709\ncLnxCreare\nn[::1]:55147->[::1]:12730\n"
        #expect(PortListener.parse(out) == [PortListener(pid: 8349, command: "lnx-server")])
    }

    @Test("同じプロセスが二つの port で待ち受けていても一つ")
    func dedupes() {
        let out = "p1\nclnx-server\nn[::1]:12731\nn*:12730\n"
        #expect(PortListener.parse(out).count == 1)
    }

    @Test("常駐していないのに外のプロセスが握っていれば portTaken（開始を出さない）")
    func takenWhileOff() {
        let phase = ServerPhase.resolve(registration: .notRegistered, job: nil, legacyInstalled: false, listeners: [terminal])
        #expect(phase == .portTaken(terminal, registration: .notRegistered))
        #expect(phase.actions.isEmpty)
        #expect(!phase.isRunning)
    }

    @Test("登録済みで落ち続けているなら portTaken で、停止（常駐をやめる）だけ出す")
    func takenWhileLooping() {
        let phase = ServerPhase.resolve(registration: .enabled, job: loopingJob, legacyInstalled: false, listeners: [terminal])
        #expect(phase == .portTaken(terminal, registration: .enabled))
        #expect(phase.actions == [.stop])
        #expect(phase.stopTitle == "停止（ログイン時にも立ち上げない）")
    }

    @Test("許可待ちのときは落ち続けてはいない。「登録をやめる」だけ出し、許可しても握られていると落ちると案内する")
    func takenWhileAwaitingApproval() {
        let phase = ServerPhase.resolve(registration: .requiresApproval, job: nil, legacyInstalled: false, listeners: [terminal])
        #expect(phase == .portTaken(terminal, registration: .requiresApproval))
        #expect(phase.actions == [.stop])
        #expect(phase.stopTitle == "登録をやめる")
        #expect(phase.detail?.contains("10 秒おき") == false)
        #expect(phase.detail?.contains("許可") == true)
    }

    @Test("握っているのが常駐自身なら running のまま")
    func ownListener() {
        let own = PortListener(pid: 10, command: "lnx-server")
        #expect(ServerPhase.resolve(registration: .enabled, job: runningJob, legacyInstalled: false, listeners: [own]) == .running(pid: 10))
    }

    @Test("server:install の常駐の案内が先（握っているのはそちらなので）")
    func legacyFirst() {
        #expect(ServerPhase.resolve(registration: .notRegistered, job: nil, legacyInstalled: true, listeners: [terminal]) == .legacy(running: false))
    }

    @Test("案内には握っているプロセスと pid、止め方を出す")
    func detail() {
        let phase = ServerPhase.portTaken(terminal, registration: .notRegistered)
        #expect(phase.title.contains("68111"))
        #expect(phase.detail?.contains("server:run") == true)
        #expect(ServerPhase.portTaken(terminal, registration: .enabled).detail?.contains("10 秒おき") == true)
    }
}

@MainActor
@Suite("待ち受けの守り（操作）")
struct PortGuardModelTests {
    let terminal = PortListener(pid: 68111, command: "lnx-server")

    @Test("外のプロセスが握っていれば、開始しても登録しない")
    func startRefuses() async {
        let residency = FakeResidency(registration: .notRegistered)
        residency.portListeners = [terminal]
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        #expect(!residency.calls.contains("register"))
        #expect(model.lastError?.contains("68111") == true)
        // メニューも案内になる（開始を出さない）
        #expect(model.phase == .portTaken(terminal, registration: .notRegistered))
        #expect(model.phase.actions.isEmpty)
    }

    @Test("見張りの読み直しで、外のプロセスが握っていれば案内になる")
    func refreshShowsPortTaken() async {
        let residency = FakeResidency(registration: .notRegistered)
        residency.portListeners = [terminal]
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.refresh()
        #expect(model.phase == .portTaken(terminal, registration: .notRegistered))
    }

    @Test("常駐が走っているあいだの見張りでは lsof を回さない")
    func refreshSkipsListenersWhileRunning() async {
        let residency = FakeResidency(registration: .enabled, settled: LaunchdJob(state: "running", pid: 10, lastExit: nil))
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.refresh()
        #expect(residency.listenerReads == 0)
        residency.settled = nil
        await model.refresh()
        #expect(residency.listenerReads == 1)
    }

    @Test("開始の直後（launchd を読んだあとに常駐が bind した）でも、常駐自身を外のものと取り違えない")
    func refreshRereadsJob() async {
        let residency = FakeResidency(registration: .enabled)
        // 1 回目の launchctl はまだ spawn 前、lsof の時点では常駐（pid 10）が待ち受けている
        residency.queue = [LaunchdJob(state: "spawn scheduled", pid: nil, lastExit: nil)]
        residency.settled = LaunchdJob(state: "running", pid: 10, lastExit: nil)
        residency.portListeners = [PortListener(pid: 10, command: "lnx-server")]
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.refresh()
        #expect(model.phase == .running(pid: 10))
    }

    @Test("開始の確認でも、常駐自身を外のものと取り違えない（KeepAlive がちょうど起こし直した）")
    func startRereadsJob() async {
        let residency = FakeResidency(registration: .enabled)
        // 1 回目の launchctl は落ちたあと、lsof の時点では起こし直された常駐（pid 10）が待ち受けている
        residency.queue = [LaunchdJob(state: "spawn scheduled", pid: nil, lastExit: "1")]
        residency.settled = LaunchdJob(state: "running", pid: 10, lastExit: nil)
        residency.portListeners = [PortListener(pid: 10, command: "lnx-server")]
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        #expect(model.lastError == nil)
        #expect(residency.calls.contains("register"))
    }

    @Test("外のプロセスが握っていれば、再起動もしない（解除も登録もしない）")
    func restartRefuses() async {
        let residency = FakeResidency(registration: .enabled)
        residency.portListeners = [terminal]
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.restart()
        #expect(!residency.calls.contains("unregister"))
        #expect(!residency.calls.contains("register"))
    }

    @Test("握っているのが常駐自身なら、再起動できる")
    func restartOwn() async {
        let residency = FakeResidency(registration: .enabled, settled: LaunchdJob(state: "running", pid: 10, lastExit: nil))
        residency.portListeners = [PortListener(pid: 10, command: "lnx-server")]
        residency.onUnregister = { residency.settled = nil; residency.portListeners = [] }
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.restart()
        #expect(residency.calls.contains("register"))
    }

    @Test("停止は、外のプロセスが握っていてもできる（落ち続ける常駐を止める）")
    func stopAllowed() async {
        let residency = FakeResidency(registration: .enabled)
        residency.portListeners = [terminal]
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.stop()
        #expect(residency.calls.contains("unregister"))
    }
}
