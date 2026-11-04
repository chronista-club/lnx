import ServiceManagement
import Testing
@testable import LnxCreare

/// メニューバーの状態 — 登録（SMAppService）・launchd の今・server:install の常駐の 3 つから決める
@Suite("ServerPhase")
struct ServerPhaseTests {
    let runningJob = LaunchdJob(state: "running", pid: 4242, lastExit: "(never exited)")
    let exitedJob = LaunchdJob(state: "not running", pid: nil, lastExit: "1")

    @Test("登録済みで走っていれば running（pid つき）")
    func running() {
        #expect(ServerPhase.resolve(registration: .enabled, job: runningJob, legacyInstalled: false) == .running(pid: 4242))
    }

    @Test("登録済みで走っていなければ stopped（前の終わり方つき）")
    func stopped() {
        #expect(ServerPhase.resolve(registration: .enabled, job: exitedJob, legacyInstalled: false) == .stopped(lastExit: "1"))
        #expect(ServerPhase.resolve(registration: .enabled, job: nil, legacyInstalled: false) == .stopped(lastExit: nil))
    }

    @Test("未登録は off、承認待ちは requiresApproval、plist が無いのは broken")
    func registration() {
        #expect(ServerPhase.resolve(registration: .notRegistered, job: nil, legacyInstalled: false) == .off)
        #expect(ServerPhase.resolve(registration: .requiresApproval, job: nil, legacyInstalled: false) == .requiresApproval)
        #expect(ServerPhase.resolve(registration: .notFound, job: nil, legacyInstalled: false) == .broken)
    }

    @Test("server:install の常駐が入っていれば、登録より先にそれを言う（同じラベルなので走っているのはそちら）")
    func legacyFirst() {
        #expect(ServerPhase.resolve(registration: .notRegistered, job: runningJob, legacyInstalled: true) == .legacy(running: true))
        #expect(ServerPhase.resolve(registration: .enabled, job: nil, legacyInstalled: true) == .legacy(running: false))
    }

    @Test("アイコンが「動いている」になるのは running と、走っている legacy だけ")
    func isRunning() {
        #expect(ServerPhase.running(pid: 1).isRunning)
        #expect(ServerPhase.legacy(running: true).isRunning)
        #expect(!ServerPhase.legacy(running: false).isRunning)
        #expect(!ServerPhase.stopped(lastExit: nil).isRunning)
        #expect(!ServerPhase.off.isRunning)
        #expect(!ServerPhase.requiresApproval.isRunning)
        #expect(!ServerPhase.broken.isRunning)
    }

    @Test("前の終わり方は、一度も終わっていない・正常終了なら出さない")
    func lastExitDetail() {
        #expect(ServerPhase.stopped(lastExit: "(never exited)").detail == nil)
        #expect(ServerPhase.stopped(lastExit: "0").detail == nil)
        #expect(ServerPhase.stopped(lastExit: nil).detail == nil)
        #expect(ServerPhase.stopped(lastExit: "Killed: 9").detail?.contains("Killed: 9") == true)
    }

    @Test("server:install の常駐が入っていれば、外し方を案内する")
    func legacyDetail() {
        #expect(ServerPhase.legacy(running: true).detail?.contains("mise run server:uninstall") == true)
    }
}

/// SMAppService.Status の写し。一度も登録していない同梱 agent は .notFound を返す（midistage の実測 2026-10-11）
@Suite("Registration")
struct RegistrationTests {
    @Test("notFound は、同梱の plist があれば未登録、無ければ壊れたビルド")
    func notFound() {
        #expect(Registration(.notFound, plistInBundle: true) == .notRegistered)
        #expect(Registration(.notFound, plistInBundle: false) == .notFound)
    }

    @Test("ほかはそのまま写す")
    func others() {
        #expect(Registration(.enabled, plistInBundle: true) == .enabled)
        #expect(Registration(.notRegistered, plistInBundle: true) == .notRegistered)
        #expect(Registration(.requiresApproval, plistInBundle: true) == .requiresApproval)
    }
}
