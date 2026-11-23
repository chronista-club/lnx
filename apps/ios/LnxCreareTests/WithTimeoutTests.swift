import Foundation
import Synchronization
import Testing
@testable import LnxCreare

/// 期限つき await。cancel に応じない処理でも期限で戻れること（club-unison 2.2 までがこの形だった。deep レビュー P3-1）
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

    @Test("最初から cancel されていたら、処理を始めずに戻る（接続を張ってから閉じない）")
    func preCancelledDoesNotStart() async throws {
        let started = Mutex(0)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await withTimeout(seconds: 1) {
                started.withLock { $0 += 1 }
                return 1
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(50))
        #expect(started.withLock { $0 } == 0)
    }

    @Test("外から cancel したら、cancel に応じる処理にも cancel が届く")
    func outerCancelReachesCooperativeWork() async throws {
        let cancelledInside = Mutex(false)
        let task = Task {
            try await withTimeout(seconds: 10) { () async throws -> Int in
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    cancelledInside.withLock { $0 = true }
                    throw error
                }
                return 1
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await waitUntil { cancelledInside.withLock { $0 } }
    }

    @Test("処理の失敗はそのまま投げる")
    func propagatesError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await withTimeout(seconds: 1) { () async throws -> Int in throw Boom() }
        }
    }
}

/// cancel に応じない待ち（club-unison 2.2 までの continuation と同じ形）
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
