import Foundation
import Testing
@testable import LnxCreare

/// メニューの操作 — 開始 = 登録、停止 = 登録の解除、再起動 = 解除 → 前のプロセスが消えるのを待つ → 登録
/// （SMAppService の unregister は reap を待たない。待たずに登録すると新しいサーバが port を取り合う）
@MainActor
@Suite("ServerMenuModel")
struct ServerMenuModelTests {
    let running = LaunchdJob(state: "running", pid: 4242, lastExit: "(never exited)")

    @Test("未登録から開始すると登録し、状態を読み直す")
    func startRegisters() async {
        let residency = FakeResidency(registration: .notRegistered)
        residency.onRegister = { [running] in
            residency.registration = .enabled
            residency.settled = running
        }
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        // 先頭の job は守り（launchd の外のプロセスが待ち受けを握っていないか）、最後は読み直し
        #expect(residency.calls == ["job", "register", "job"])
        #expect(model.phase == .running(pid: 4242))
        #expect(model.lastError == nil)
    }

    @Test("server:install の常駐が入っていれば、開始しても登録しない（同じラベルを取り合わない）")
    func startRefusesWithLegacy() async {
        let residency = FakeResidency(registration: .notRegistered, legacy: true)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        #expect(!residency.calls.contains("register"))
        #expect(model.lastError?.contains("server:uninstall") == true)
        #expect(model.phase == .legacy(running: false))
    }

    @Test("server:install の常駐が入っていれば、再起動もしない（解除も登録もしない）")
    func restartRefusesWithLegacy() async {
        let residency = FakeResidency(registration: .enabled, legacy: true)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.restart()
        #expect(residency.calls == ["job"])
        #expect(model.lastError?.contains("server:uninstall") == true)
    }

    @Test("登録済みで止まっていれば、開始は再起動と同じ（解除 → 登録）")
    func startWhenStoppedReRegisters() async {
        let residency = FakeResidency(registration: .enabled)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        #expect(residency.calls.filter { $0 != "job" } == ["unregister", "register"])
    }

    @Test("停止は登録の解除（ログイン時にも立ち上がらない）")
    func stopUnregisters() async {
        let residency = FakeResidency(registration: .enabled, settled: running)
        residency.onUnregister = {
            residency.registration = .notRegistered
            residency.settled = nil
        }
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.stop()
        #expect(residency.calls == ["unregister", "job"])
        #expect(model.phase == .off)
    }

    @Test("再起動は、前のプロセスが launchd から消えるのを待ってから登録する")
    func restartWaitsForReap() async {
        let residency = FakeResidency(registration: .enabled)
        var pauses = 0
        let model = ServerMenuModel(residency: residency, pause: { _ in pauses += 1 })
        // 解除のあと 2 回はまだ居る、3 回目に消える
        residency.onUnregister = { [running] in residency.queue = [running, running] }
        await model.restart()
        #expect(residency.calls == ["job", "unregister", "job", "job", "job", "register", "job"])
        #expect(pauses == 2)
    }

    @Test("前のプロセスが消えなくても、待ちには上限がある（そのあと登録して launchd に任せる）")
    func restartGivesUp() async {
        let residency = FakeResidency(registration: .enabled, settled: running)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.restart()
        // 解除してから登録するまでに見る回数（解除の前の job は守り）
        let afterUnregister = residency.calls.drop { $0 != "unregister" }
        let reapWait = afterUnregister.prefix { $0 != "register" }
        #expect(reapWait.filter { $0 == "job" }.count == ServerMenuModel.reapChecks)
        #expect(residency.calls.contains("register"))
    }

    @Test("未登録のまま再起動しても、解除の失敗（未登録）では止まらない")
    func restartFromUnregistered() async {
        let residency = FakeResidency(registration: .notRegistered)
        residency.unregisterError = NSError(domain: "SMAppServiceErrorDomain", code: 3)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.restart()
        #expect(residency.calls.contains("register"))
        #expect(model.lastError == nil)
    }

    @Test("失敗はメニューに出す")
    func surfacesErrors() async {
        let residency = FakeResidency(registration: .notRegistered)
        residency.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        #expect(model.lastError?.contains("Operation not permitted") == true)
    }

    @Test("次の操作が成功したら、前の失敗は消す")
    func clearsError() async {
        let residency = FakeResidency(registration: .notRegistered)
        residency.registerError = NSError(domain: "x", code: 1)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.start()
        #expect(model.lastError != nil)
        residency.registerError = nil
        await model.start()
        #expect(model.lastError == nil)
    }

    @Test("読み直しは、登録・常駐・launchd の今から状態を決める")
    func refresh() async {
        let residency = FakeResidency(registration: .requiresApproval)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.refresh()
        #expect(model.phase == .requiresApproval)
    }

    @Test("稼働中は GearProbe から Gear 一覧とサマリを更新し、停止したら閉じてクリアし、再稼働で再び Probe する")
    func gearProbeLifecycleAndSummaryLine() async {
        let residency = FakeResidency(registration: .enabled, settled: running)
        let probe = FakeGearProbe(
            result: GearProbeResult(
                connected: true,
                serviceVersion: "0.1.0-alpha3",
                serviceExecutable: "/Applications/LnxCreare.app/Contents/MacOS/lnx-server",
                summary: GearSummary(present: 2, releasingStuck: 1, errors: 1),
                gears: [
                    GearFacts(
                        id: "roto", name: "Roto-Control", present: true, assignedTo: "vp",
                        revision: 1, held: true, phase: "active", maker: "Melbourne Instruments",
                        model: "ROTO-CONTROL"
                    ),
                    GearFacts(
                        id: "maru", name: "maru", present: true, assignedTo: "ladyland",
                        revision: 2, held: true, phase: "releasing", releasingTo: "vp",
                        error: "timeout", releasingStuck: true, hasGearAsset: false
                    ),
                ]
            )
        )
        let model = ServerMenuModel(residency: residency, gearProbe: probe, pause: { _ in })
        await model.refresh()
        #expect(model.phase == .running(pid: 4242))
        #expect(probe.probeCalls == 1)
        #expect(model.gearRows.count == 2)
        #expect(model.gearServiceVersion == "0.1.0-alpha3")
        #expect(model.gearSummaryLine == "Gear: 2 台接続 / エラー 1 件 / 引き継ぎ待ち 1 件")

        // 停止すると probe.close() が呼ばれ、一覧・サマリがクリアされる
        residency.onUnregister = {
            residency.registration = .notRegistered
            residency.settled = nil
        }
        await model.stop()
        #expect(probe.closeCalls >= 1)
        #expect(model.gearRows.isEmpty)
        #expect(model.gearSummary == GearSummary(present: 0, releasingStuck: 0, errors: 0))
        #expect(model.gearServiceVersion == nil)
        #expect(model.gearSummaryLine == nil)

        // 再び開始すると、一度 close() された後でも再度 probe() して一覧が復活する
        residency.onRegister = { [running] in
            residency.registration = .enabled
            residency.settled = running
        }
        await model.start()
        #expect(probe.probeCalls == 2)
        #expect(model.gearRows.count == 2)
    }
}

final class FakeGearProbe: GearProbing, @unchecked Sendable {
    var result: GearProbeResult
    var probeCalls = 0
    var closeCalls = 0

    init(result: GearProbeResult) {
        self.result = result
    }

    func probe() async -> GearProbeResult {
        probeCalls += 1
        return result
    }

    func close() async {
        closeCalls += 1
    }
}

/// SMAppService と launchctl の代わり。呼ばれた順を残す（読むほうは job だけ）
@MainActor
final class FakeResidency: ServerResidency {
    var registration: Registration
    var legacy: Bool
    /// job() は queue を先頭から 1 つずつ返し、尽きたら settled を返す（nil = launchd に居ない）
    var queue: [LaunchdJob] = []
    var settled: LaunchdJob?
    /// 12730 / 12731 で待ち受けているプロセス（守りの試験）
    var portListeners: [PortListener] = []
    var calls: [String] = []
    var registerError: Error?
    var unregisterError: Error?
    var onRegister: () -> Void = {}
    var onUnregister: () -> Void = {}

    init(registration: Registration, legacy: Bool = false, settled: LaunchdJob? = nil) {
        self.registration = registration
        self.legacy = legacy
        self.settled = settled
    }

    func currentRegistration() -> Registration { registration }
    func legacyInstalled() -> Bool { legacy }

    func register() throws {
        calls.append("register")
        if let registerError { throw registerError }
        onRegister()
    }

    func unregister() async throws {
        calls.append("unregister")
        if let unregisterError { throw unregisterError }
        onUnregister()
    }

    func job() async -> LaunchdJob? {
        calls.append("job")
        return queue.isEmpty ? settled : queue.removeFirst()
    }

    /// lsof を回した回数（calls には入れない。呼び順の試験を守りの読みに縛らない）
    var listenerReads = 0
    func listeners() async -> [PortListener] {
        listenerReads += 1
        return portListeners
    }
}
