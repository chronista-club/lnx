import Testing
@testable import LnxCreare

@Suite("BackoffPolicy")
struct BackoffPolicyTests {
    @Test("1 回目は 0.5 秒、以後倍々、上限は 10 秒")
    func doubles() {
        let policy = BackoffPolicy()
        #expect(policy.delay(attempt: 1) == .milliseconds(500))
        #expect(policy.delay(attempt: 2) == .seconds(1))
        #expect(policy.delay(attempt: 3) == .seconds(2))
        #expect(policy.delay(attempt: 4) == .seconds(4))
        #expect(policy.delay(attempt: 10) == .seconds(10))
    }

    @Test("0 回目や負の回数も最初の間を返す")
    func clampsLow() {
        let policy = BackoffPolicy()
        #expect(policy.delay(attempt: 0) == .milliseconds(500))
        #expect(policy.delay(attempt: -3) == .milliseconds(500))
    }
}
