import Foundation

/// つなぎ直すまでの間。倍々で延ばし、上限で止める
struct BackoffPolicy: Sendable, Equatable {
    var base: Duration = .milliseconds(500)
    var max: Duration = .seconds(10)

    func delay(attempt: Int) -> Duration {
        let exponent = Swift.max(attempt, 1) - 1
        var delay = base
        for _ in 0..<Swift.min(exponent, 30) {
            delay = delay * 2
            if delay >= max { return max }
        }
        return Swift.min(delay, max)
    }
}
