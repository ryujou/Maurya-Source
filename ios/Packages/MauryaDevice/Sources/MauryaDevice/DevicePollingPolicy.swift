public struct DevicePollingPolicy: Equatable, Sendable {
    public var successInterval: Duration
    public var retryInterval: Duration
    public var maximumConsecutiveFailures: Int

    public init(
        successInterval: Duration = .seconds(2),
        retryInterval: Duration = .milliseconds(500),
        maximumConsecutiveFailures: Int = 3
    ) throws {
        guard successInterval > .zero, retryInterval > .zero,
            maximumConsecutiveFailures > 0
        else {
            throw DeviceFailure(.invalidState, detail: "Polling values must be positive")
        }
        self.successInterval = successInterval
        self.retryInterval = retryInterval
        self.maximumConsecutiveFailures = maximumConsecutiveFailures
    }

    public func decision(afterConsecutiveFailures failures: Int) -> DevicePollingDecision {
        guard failures > 0 else { return .continueAfter(successInterval) }
        guard failures < maximumConsecutiveFailures else { return .stop }
        return .continueAfter(retryInterval)
    }
}

public enum DevicePollingDecision: Equatable, Sendable {
    case continueAfter(Duration)
    case stop
}
