import Foundation
import Testing

@testable import MauryaOTA

@Suite("Secure OTA workflow")
struct OTAWorkflowTests {
    @Test("Completes only after commit, reconnect, and target-version confirmation")
    func successfulUpdate() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport()
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        let result = try await workflow(transport: transport, network: network, store: store)
            .run(deviceID: "device-A")

        #expect(result.stage == .succeeded)
        #expect(result.installedVersion == "1.9.0")
        let metrics = await transport.metrics()
        #expect(metrics.began == 1)
        #expect(metrics.committed == 1)
        #expect(metrics.reconnects >= 1)
        #expect(metrics.offsets == [0, 50, 100])
        #expect(await store.value("device-A") == nil)
        #expect(await store.saveCount() == 8)
    }

    @Test("Lost acknowledgement resumes from device status without duplicating bytes")
    func lostAcknowledgementRecovery() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .loseAcknowledgementOnce(offset: 50))
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        let result = try await workflow(transport: transport, network: network, store: store)
            .run(deviceID: "device-B")

        #expect(result.stage == .succeeded)
        let metrics = await transport.metrics()
        #expect(metrics.offsets == [0, 50, 100])
        #expect(metrics.reconnects >= 2)
    }

    @Test(
        "Live device offset wins over a persisted checkpoint",
        arguments: [
            ResumeCase(liveOffset: 25, expectedOffsets: [25, 75]),
            ResumeCase(liveOffset: 50, expectedOffsets: [50, 100]),
            ResumeCase(liveOffset: 75, expectedOffsets: [75]),
        ]
    )
    func persistedResume(resumeCase: ResumeCase) async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(
            deviceOffset: resumeCase.liveOffset,
            expectedBytes: UInt32(artifact.count)
        )
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        var checkpoint = OTACheckpoint(
            deviceID: "device-C",
            manifest: manifest,
            entityTag: "fixture-etag"
        )
        checkpoint.confirmedOffset = 50
        await store.save(checkpoint)

        _ = try await workflow(transport: transport, network: network, store: store)
            .run(deviceID: "device-C")

        let metrics = await transport.metrics()
        #expect(metrics.began == 0)
        #expect(metrics.offsets == resumeCase.expectedOffsets)
    }

    @Test("A definite pre-send commit failure remains retryable across workflows")
    func commitPreSendFailureRecovery() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .commitFailsBeforeSendOnce)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        await expectFailure(.protocolViolation("injected pre-send failure")) {
            try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "device-pre-send")
        }
        let failedCheckpoint = await store.value("device-pre-send")
        #expect(failedCheckpoint?.commitState == .verified)
        #expect(failedCheckpoint?.didCommit == false)
        #expect(await transport.metrics().committed == 0)

        let result = try await workflow(transport: transport, network: network, store: store)
            .run(deviceID: "device-pre-send")

        #expect(result.stage == .succeeded)
        let metrics = await transport.metrics()
        #expect(metrics.began == 1)
        #expect(metrics.offsets == [0, 50, 100])
        #expect(metrics.committed == 1)
        #expect(await store.value("device-pre-send") == nil)
    }

    @Test("Lost commit response reconciles an already rebooted device on the next workflow")
    func commitResponseLossRecovery() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .commitResponseLostAndReconnectFailsOnce)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        let oneReconnectAttempt = OTAWorkflowPolicy(maximumReconnectAttempts: 0)

        await expectFailure(.reconnectFailed) {
            try await workflow(
                transport: transport,
                network: network,
                store: store,
                policy: oneReconnectAttempt
            ).run(deviceID: "device-response-loss")
        }
        let unknownCheckpoint = await store.value("device-response-loss")
        #expect(unknownCheckpoint?.commitState == .requestOutcomeUnknown)
        #expect(unknownCheckpoint?.didCommit == true)
        #expect(await transport.metrics().committed == 1)

        let result = try await workflow(
            transport: transport,
            network: network,
            store: store,
            policy: oneReconnectAttempt
        ).run(deviceID: "device-response-loss")

        #expect(result.stage == .upToDate)
        #expect(await transport.metrics().committed == 1)
        #expect(await store.value("device-response-loss") == nil)
    }

    @Test("Bad detached signature is a hard failure before artifact download or BLE begin")
    func invalidSignature() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport()
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        let subject = workflow(
            transport: transport,
            network: network,
            store: store,
            verifier: .init(failure: .invalidSignature)
        )

        await expectFailure(.invalidSignature) {
            try await subject.run(deviceID: "device-D")
        }
        #expect(await network.artifactFetchCount() == 0)
        #expect(await transport.metrics().began == 0)
    }

    @Test("Altered artifact hash is rejected before device preparation")
    func alteredArtifact() async throws {
        let (manifest, artifact) = fixture()
        var altered = artifact
        altered[0] ^= 0xff
        let transport = FakeOTADeviceTransport()
        let network = try FakeOTANetwork(
            manifest: manifest,
            artifactBytes: artifact,
            artifactOverride: altered
        )
        let store = MemoryCheckpointStore()

        await expectFailure(.artifactHashMismatch) {
            try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "device-E")
        }
        #expect(await transport.metrics().began == 0)
    }

    @Test("Wrong chunk acknowledgement stops transfer and never commits")
    func wrongAcknowledgement() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .badAcknowledgement)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        await expectFailure(.invalidAcknowledgedOffset(expected: 50, actual: 51)) {
            try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "device-F")
        }
        #expect(await transport.metrics().committed == 0)
    }

    @Test("Firmware verification error remains a hard failure")
    func firmwareVerificationFailure() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .verificationFailure(code: 0x109))
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        await expectFailure(.deviceVerificationFailed(0x109)) {
            try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "device-G")
        }
        #expect(await transport.metrics().committed == 0)
    }

    @Test("Verification polling is bounded")
    func verificationTimeout() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .neverVerifies)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        let policy = OTAWorkflowPolicy(maximumVerificationPolls: 2)

        await expectFailure(.verificationTimedOut) {
            try await workflow(
                transport: transport,
                network: network,
                store: store,
                policy: policy
            ).run(deviceID: "device-H")
        }
    }

    @Test("Lifecycle task cancellation preserves checkpoint for foreground reconciliation")
    func cancellation() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .neverVerifies)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        let subject = OTAWorkflow(
            transport: transport,
            network: network,
            signatureVerifier: FakeSignatureVerifier(),
            checkpointStore: store,
            appVersion: 421,
            allowedArtifactHosts: ["xtbang.top"],
            sleeper: .init { _ in throw CancellationError() }
        )

        await expectFailure(.cancelled) {
            try await subject.run(deviceID: "device-cancel")
        }
        #expect(await transport.metrics().cancelled == 0)
        #expect(await transport.metrics().committed == 0)
        #expect(await store.value("device-cancel") != nil)
    }

    @Test("A returned device with unchanged firmware is never reported successful")
    func versionUnchanged() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(mode: .unchangedAfterCommit)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        await expectFailure(.installedVersionUnchanged(expected: "1.9.0", actual: "1.8.0")) {
            try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "device-I")
        }
        #expect(await store.value("device-I")?.didCommit == true)
        #expect(await store.value("device-I")?.commitState == .confirmed)
    }

    struct ResumeCase: Sendable, CustomTestStringConvertible {
        let liveOffset: UInt32
        let expectedOffsets: [UInt32]

        var testDescription: String { "live-\(liveOffset)" }
    }

    @Test("Transport write capacity must leave at least one firmware byte")
    func invalidCapacity() async throws {
        let (manifest, artifact) = fixture()
        let transport = FakeOTADeviceTransport(chunkCapacity: 0)
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        await expectFailure(.invalidWriteCapacity(0)) {
            try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "device-J")
        }
    }

    private func expectFailure(
        _ expected: OTAFailure,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let actual as OTAFailure {
            #expect(actual == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
