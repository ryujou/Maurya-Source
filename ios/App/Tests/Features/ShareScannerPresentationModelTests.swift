import Testing

@testable import Maurya

@MainActor
struct ShareScannerPresentationModelTests {
    @Test func supportedScannerMovesThroughLifecycleAndCanRetry() {
        let model = ShareScannerPresentationModel(canAttemptScanning: true)
        #expect(model.state == .loading)

        model.scannerDidStart()
        #expect(model.state == .running)

        model.scannerWillStart()
        #expect(model.state == .loading)

        model.scannerBecameUnavailable()
        #expect(model.state == .unavailable)

        model.retry(canAttemptScanning: true)
        #expect(model.state == .loading)
        #expect(model.retryGeneration == 1)
    }

    @Test func unavailableFixtureNeverClaimsCameraSuccess() {
        let model = ShareScannerPresentationModel(canAttemptScanning: false)
        #expect(model.state == .unavailable)

        model.retry(canAttemptScanning: false)

        #expect(model.state == .unavailable)
        #expect(model.retryGeneration == 1)
    }
}
