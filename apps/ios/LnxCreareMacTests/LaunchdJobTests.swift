import Testing
@testable import LnxCreare

/// launchctl print の一段目（タブ 1 つ）から、常駐の今を拾う（tasks/_lib/agent.rb の parse_state と同じ読み方）
@Suite("LaunchdJob")
struct LaunchdJobTests {
    /// SMAppService で載った agent の実物（midistaged、2026-11-05）を縮めたもの。入れ子の state を混ぜてある
    static let runningOutput = """
        gui/501/tech.anycreative.lnx-server = {
        \tactive count = 1
        \tpath = (submitted by smd.353)
        \ttype = Submitted
        \tmanaged_by = com.apple.xpc.ServiceManagement
        \tstate = running

        \tprogram identifier = Contents/MacOS/lnx-server (mode: 2)
        \tparent bundle identifier = tech.anycreative.lnx.creare
        \truns = 1
        \tpid = 69784
        \tlast exit code = (never exited)

        \tresource coalition = {
        \t\tID = 9226
        \t\tstate = active
        \t}
        }
        """

    @Test("走っている: state / pid / 前の終わり方")
    func running() {
        let job = LaunchdJob.parse(Self.runningOutput)
        #expect(job == LaunchdJob(state: "running", pid: 69784, lastExit: "(never exited)"))
        #expect(job.isRunning)
    }

    @Test("止まっている: pid は無く、シグナルで終わったならそれを前の終わり方にする")
    func stoppedBySignal() {
        let out = """
            gui/501/tech.anycreative.lnx-server = {
            \tstate = not running
            \truns = 3
            \tlast exit code = 0
            \tlast terminating signal = Killed: 9
            }
            """
        let job = LaunchdJob.parse(out)
        #expect(job == LaunchdJob(state: "not running", pid: nil, lastExit: "Killed: 9"))
        #expect(!job.isRunning)
    }

    @Test("入れ子（タブ 2 つ）の state は拾わない")
    func ignoresNested() {
        let out = "gui/501/x = {\n\t\tstate = active\n}"
        #expect(LaunchdJob.parse(out) == LaunchdJob(state: nil, pid: nil, lastExit: nil))
    }

    @Test("running でも pid が無ければ走っているとはみなさない")
    func runningWithoutPid() {
        #expect(!LaunchdJob(state: "running", pid: nil, lastExit: nil).isRunning)
    }
}
