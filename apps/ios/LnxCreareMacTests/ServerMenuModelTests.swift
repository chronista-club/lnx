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
        #expect(residency.calls == ["register", "job"])
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
        #expect(residency.calls == ["unregister", "job", "job", "job", "register", "job"])
        #expect(pauses == 2)
    }

    @Test("前のプロセスが消えなくても、待ちには上限がある（そのあと登録して launchd に任せる）")
    func restartGivesUp() async {
        let residency = FakeResidency(registration: .enabled, settled: running)
        let model = ServerMenuModel(residency: residency, pause: { _ in })
        await model.restart()
        let beforeRegister = residency.calls.prefix { $0 != "register" }
        #expect(beforeRegister.filter { $0 == "job" }.count == ServerMenuModel.reapChecks)
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
}

/// SMAppService と launchctl の代わり。呼ばれた順を残す（読むほうは job だけ）
@MainActor
final class FakeResidency: ServerResidency {
    var registration: Registration
    var legacy: Bool
    /// job() は queue を先頭から 1 つずつ返し、尽きたら settled を返す（nil = launchd に居ない）
    var queue: [LaunchdJob] = []
    var settled: LaunchdJob?
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
}
