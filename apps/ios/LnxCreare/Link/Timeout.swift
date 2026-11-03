import Foundation
import Synchronization

/// 期限つき await（超えたら LinkTimeout）。
///
/// club-unison の待ちは cancel に応じない（continuation を待つだけ）。`withThrowingTaskGroup` で組むと、
/// 期限が来ても子が終わるまで戻れず、設計の「timeout なしで await しない」が崩れる（deep レビュー P3-1）。
/// だから処理と期限を構造化しない Task で競わせ、先に終わった方で一度だけ戻る。外からの cancel でもすぐ戻る。
/// 戻ったあとに処理が遅れて成功したら、その値を `onLateSuccess` に渡す（接続を閉じ忘れない）
func withTimeout<T: Sendable>(
    seconds: Double,
    onLateSuccess: (@Sendable (T) async -> Void)? = nil,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let gate = TimeoutGate<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            let work = Task {
                do {
                    let value = try await operation()
                    if !gate.finish(.success(value)) { await onLateSuccess?(value) }
                } catch {
                    gate.finish(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.finish(.failure(LinkTimeout(seconds: seconds))) { work.cancel() }
            }
        }
    } onCancel: {
        gate.finish(.failure(CancellationError()))
    }
}

struct LinkTimeout: Error, CustomStringConvertible {
    let seconds: Double
    var description: String { "\(seconds) 秒待っても応答がない" }
}

/// 一度だけ開く戸。最初の finish だけが continuation を進める（install より先に来たら結果を預かる）
private final class TimeoutGate<T: Sendable>: Sendable {
    private struct State: ~Copyable {
        var continuation: CheckedContinuation<T, any Error>?
        var early: Result<T, any Error>?
        var finished = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        let early = state.withLock { s -> Result<T, any Error>? in
            if let early = s.early {
                s.early = nil
                return early
            }
            s.continuation = continuation
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    /// 最初の 1 回だけ true
    @discardableResult
    func finish(_ result: Result<T, any Error>) -> Bool {
        let (first, continuation) = state.withLock { s -> (Bool, CheckedContinuation<T, any Error>?) in
            guard !s.finished else { return (false, nil) }
            s.finished = true
            guard let continuation = s.continuation else {
                s.early = result
                return (true, nil)
            }
            s.continuation = nil
            return (true, continuation)
        }
        continuation?.resume(with: result)
        return first
    }
}
