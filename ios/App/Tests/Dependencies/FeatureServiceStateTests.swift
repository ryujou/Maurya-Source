import Foundation
import MauryaOTA
import Testing

@testable import Maurya

@MainActor
struct FeatureServiceStateTests {
    @Test func fakeAnalysisStartAndStopFollowLifecycle() {
        let service = FakeAnalysisControlService()
        service.start(.motion)
        #expect(service.state == .running(.motion))
        service.stop()
        #expect(service.state == .idle)
    }

    @Test func virtualAnalysisModeAndSensitivityAreExplicitState() {
        let service = FakeAnalysisControlService()
        service.setVirtualInputsEnabled(true)
        #expect(service.virtualInputsEnabled)
        #expect(service.state == .running(.virtual))
        service.setAudioSensitivity(2.5)
        #expect(service.audioSensitivity == 2.5)
        service.setVirtualInputsEnabled(false)
        #expect(service.state == .idle)
    }

    @Test func fakePlaybackDisconnectStopsSuccessfulState() {
        let service = FakePlaybackControlService()
        service.start()
        #expect(service.state == .running)
        service.connectionLost()
        #expect(service.state == .failed("playback.disconnected"))
    }

    @Test func otaPreflightNeverClaimsReadyWithoutEndpointAndKey() {
        let service = LiveOTAAvailabilityService(environment: [:])
        guard case .unavailable(let blockers) = service.preflight else {
            Issue.record("Expected explicit unavailable preflight")
            return
        }
        #expect(blockers.contains("ota.preflight.network"))
        #expect(blockers.contains("ota.preflight.production-key"))
    }

    @Test func otaBundledProductionConfigurationPassesStaticPreflight() {
        let service = LiveOTAAvailabilityService()
        #expect(service.preflight == .ready)
        #expect(service.canStart == false)
    }

    @Test func otaPreflightCanBecomeReadyOnlyWithBothInputs() {
        let service = LiveOTAAvailabilityService(environment: [
            "baseURL": "https://firmware.example.com/ota",
            "publicKey": Data("fixture-key".utf8).base64EncodedString(),
            "keyID": "fixture",
        ])
        #expect(service.preflight == .ready)
        #expect(service.canStart == false)
    }

    @Test func otaStartRequiresBothProductionConfigurationAndConnectedContext() {
        let transport = FakeOTADeviceTransport()
        let service = LiveOTAAvailabilityService(
            environment: [
                "baseURL": "https://firmware.example.com/ota",
                "publicKey": Data("fixture-key".utf8).base64EncodedString(),
                "keyID": "fixture",
            ],
            contextProvider: {
                DeviceOTAContext(deviceID: "device", unitID: 1, transport: transport)
            }
        )
        #expect(service.preflight == .ready)
        #expect(service.canStart)
    }
}

private actor FakeOTADeviceTransport: OTADeviceTransport {
    func transact(_ request: Data, timeout: Duration) async throws -> Data { Data() }
    func maximumFirmwareChunkByteCount() async throws -> Int { 64 }
    func reconnectAndWait(timeout: Duration) async throws {}
}
