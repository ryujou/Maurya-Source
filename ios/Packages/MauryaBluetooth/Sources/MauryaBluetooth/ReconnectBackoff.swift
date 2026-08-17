import Foundation

public struct ReconnectBackoffPolicy: Sendable, Equatable {
    public let initialDelay: Duration
    public let multiplier: Int
    public let maximumDelay: Duration

    public init(
        initialDelay: Duration = .seconds(1),
        multiplier: Int = 2,
        maximumDelay: Duration = .seconds(45)
    ) {
        precondition(initialDelay > .zero)
        precondition(multiplier >= 1)
        precondition(maximumDelay >= initialDelay)
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maximumDelay = maximumDelay
    }

    public func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return .zero }
        var delay = initialDelay
        for _ in 1..<attempt {
            if delay >= maximumDelay { return maximumDelay }
            delay *= multiplier
        }
        return min(delay, maximumDelay)
    }
}
