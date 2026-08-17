import Testing

@testable import MauryaBluetooth

struct ReconnectBackoffTests {
    @Test(
        "Exponential reconnect delay is capped at Android's 45-second ceiling",
        arguments: [
            (attempt: 0, expected: Duration.zero),
            (attempt: 1, expected: Duration.seconds(1)),
            (attempt: 2, expected: Duration.seconds(2)),
            (attempt: 3, expected: Duration.seconds(4)),
            (attempt: 6, expected: Duration.seconds(32)),
            (attempt: 7, expected: Duration.seconds(45)),
            (attempt: 20, expected: Duration.seconds(45)),
        ]
    )
    func delay(attempt: Int, expected: Duration) {
        #expect(ReconnectBackoffPolicy().delay(forAttempt: attempt) == expected)
    }
}
