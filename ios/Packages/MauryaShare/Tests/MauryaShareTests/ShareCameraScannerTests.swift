import Testing

@testable import MauryaShare

struct ShareCameraScannerTests {
    @Test func lifecycleStopsUntilEverySuspensionEnds() {
        var machine = ShareCameraScannerStateMachine()
        var fake = FakeCameraSession()

        fake.apply(machine.handle(.requestStart))
        _ = machine.handle(.startSucceeded)
        fake.apply(machine.handle(.suspend(.applicationBackground)))
        fake.apply(machine.handle(.suspend(.sessionInterruption)))
        fake.apply(machine.handle(.resume(.applicationBackground)))

        #expect(machine.state == .suspended([.sessionInterruption]))
        #expect(fake.configureCount == 1)
        #expect(fake.stopCount == 1)
        #expect(fake.startCount == 0)

        fake.apply(machine.handle(.resume(.sessionInterruption)))
        #expect(machine.state == .running)
        #expect(fake.startCount == 1)
    }

    @Test func stopIsIdempotentAndFinishesOnce() {
        var machine = ShareCameraScannerStateMachine()
        var fake = FakeCameraSession()
        fake.apply(machine.handle(.requestStart))
        _ = machine.handle(.startSucceeded)
        fake.apply(machine.handle(.requestStop))
        fake.apply(machine.handle(.requestStop))

        #expect(machine.state == .stopped)
        #expect(fake.stopCount == 1)
        #expect(fake.finishCount == 1)
    }

    @Test func cancellationAndFailureShareDeterministicCleanupActions() {
        var cancelled = ShareCameraScannerStateMachine()
        _ = cancelled.handle(.requestStart)
        _ = cancelled.handle(.startSucceeded)
        let cancellationActions = cancelled.handle(.cancel)

        var failed = ShareCameraScannerStateMachine()
        _ = failed.handle(.requestStart)
        _ = failed.handle(.startSucceeded)
        let failureActions = failed.handle(.fail(.configurationFailed))

        #expect(cancellationActions == [.stopSession, .finishStream])
        #expect(failureActions == [.stopSession, .finishStream])
        #expect(failed.state == .failed(.configurationFailed))
    }

    @Test func boundedPayloadStreamKeepsOnlyNewestUnconsumedToken() async throws {
        let pair = AVFoundationShareQRCodePayloadProvider.makePayloadStream()
        pair.continuation.yield("first")
        pair.continuation.yield("second")
        pair.continuation.yield("third")
        pair.continuation.finish()

        var iterator = pair.stream.makeAsyncIterator()
        #expect(await iterator.next() == "third")
        #expect(await iterator.next() == nil)
    }
}

private struct FakeCameraSession {
    private(set) var configureCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var finishCount = 0

    mutating func apply(_ actions: [ShareCameraScannerAction]) {
        for action in actions {
            switch action {
            case .configureAndStart: configureCount += 1
            case .startSession: startCount += 1
            case .stopSession: stopCount += 1
            case .finishStream: finishCount += 1
            }
        }
    }
}
