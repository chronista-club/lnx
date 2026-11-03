import Foundation
import Synchronization
import Testing
@testable import LnxCreare

/// 期限つき await。club-unison の待ちは cancel に応じないので、応じない相手でも期限で戻れること（deep レビュー P3-1）
@Suite("withTimeout")
struct WithTimeoutTests {
    @Test("期限内に終われば値を返す")
    func returnsValue() async throws {
        let value = try await withTimeout(seconds: 1) { 42 }
        #expect(value == 42)
    }

    @Test("cancel に応じない処理でも、期限で LinkTimeout を投げて戻る")
    func timesOutNonCooperative() async throws {
        let latch = Latch()
        let clock = ContinuousClock()
        let started = clock.now
        await #expect(throws: LinkTimeout.self) {
            try await withTimeout(seconds: 0.1) { await latch.wait() }
        }
        #expect(clock.now - started < .seconds(1))
        latch.open(0)
    }

    @Test("期限のあとに遅れて成功した値は onLateSuccess に渡る（接続を閉じ忘れない）")
    func lateSuccessIsHandedOver() async throws {
        let latch = Latch()
        let late = Mutex<[Int]>([])
        await #expect(throws: LinkTimeout.self) {
            try await withTimeout(seconds: 0.05, onLateSuccess: { value in late.withLock { $0.append(value) } }) {
                await latch.wait()
            }
        }
        latch.open(7)
        try await waitUntil { late.withLock { $0 } == [7] }
    }

    @Test("外から cancel されてもすぐ戻り、遅れた値は onLateSuccess に渡る")
    func outerCancel() async throws {
        let latch = Latch()
        let late = Mutex<[Int]>([])
        let task = Task {
            try await withTimeout(seconds: 10, onLateSuccess: { value in late.withLock { $0.append(value) } }) {
                await latch.wait()
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        latch.open(9)
        try await waitUntil { late.withLock { $0 } == [9] }
    }

    @Test("処理の失敗はそのまま投げる")
    func propagatesError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await withTimeout(seconds: 1) { () async throws -> Int in throw Boom() }
        }
    }
}

/// cancel に応じない待ち（club-unison の continuation と同じ形）
final class Latch: Sendable {
    private let state = Mutex<(waiter: CheckedContinuation<Int, Never>?, value: Int?)>((nil, nil))

    func wait() async -> Int {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { s -> Int? in
                if let value = s.value { return value }
                s.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func open(_ value: Int) {
        let waiter = state.withLock { s -> CheckedContinuation<Int, Never>? in
            s.value = value
            defer { s.waiter = nil }
            return s.waiter
        }
        waiter?.resume(returning: value)
    }
}

func waitUntil(timeout: Duration = .seconds(2), _ condition: @Sendable () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("条件が \(timeout) 以内に満たされなかった")
}
