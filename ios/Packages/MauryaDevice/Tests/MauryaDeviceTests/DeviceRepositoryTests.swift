import Foundation
import MauryaBluetooth
import MauryaDevice
import Testing

struct DeviceRepositoryTests {
    @Test("Refresh reads Android's 22-register config then 35-register groups")
    func refreshSnapshot() async throws {
        let transport = QueueTransport([
            .success(readResponse(values: configurationFixture())),
            .success(readResponse(values: groupsFixture())),
        ])
        let repository = DeviceRepository(transport: transport)

        let snapshot = try await repository.refreshSnapshot()
        let requests = await transport.requests
        let state = await repository.state()

        #expect(snapshot.groups.count == 7)
        #expect(requests.count == 2)
        #expect(requests[0][4] == 0 && requests[0][5] == 22)
        #expect(requests[1][4] == 0 && requests[1][5] == 35)
        #expect(state.freshness == .current)
    }

    @Test("Disconnect during an in-flight refresh cannot publish success")
    func disconnectInvalidatesInflightWork() async {
        let transport = SuspendedTransport()
        let repository = DeviceRepository(transport: transport)
        let task = Task { try await repository.refreshSnapshot() }
        await transport.waitForRequest()

        await repository.markDisconnected()
        await transport.succeed(with: readResponse(values: configurationFixture()))

        do {
            _ = try await task.value
            Issue.record("Refresh should fail after the connection generation changes")
        } catch let failure as DeviceFailure {
            #expect(failure.category == .disconnected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let state = await repository.state()
        #expect(state.isConnected == false)
        #expect(state.freshness == .stale)
        #expect(state.snapshot == nil)
    }

    @Test("Disconnected repository rejects writes without touching transport")
    func disconnectedWrite() async {
        let transport = QueueTransport([])
        let repository = DeviceRepository(transport: transport, initiallyConnected: false)

        do {
            try await repository.applyGroup(index: 0, state: DeviceGroupState())
            Issue.record("Write should fail while disconnected")
        } catch let failure as DeviceFailure {
            #expect(failure.category == .disconnected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Bluetooth errors have stable domain categories")
    func errorClassification() {
        #expect(
            DeviceFailureClassifier.classify(BluetoothFailure(.responseTimeout)).category == .timeout
        )
        #expect(
            DeviceFailureClassifier.classify(BluetoothFailure(.queueFull)).category == .queueSaturated
        )
        #expect(
            DeviceFailureClassifier.classify(BluetoothFailure(.staleConnection)).category == .disconnected
        )
    }

    @Test("Polling policy bounds retries")
    func pollingPolicy() throws {
        let policy = try DevicePollingPolicy(
            successInterval: .seconds(2),
            retryInterval: .milliseconds(200),
            maximumConsecutiveFailures: 3
        )
        #expect(policy.decision(afterConsecutiveFailures: 0) == .continueAfter(.seconds(2)))
        #expect(policy.decision(afterConsecutiveFailures: 1) == .continueAfter(.milliseconds(200)))
        #expect(policy.decision(afterConsecutiveFailures: 2) == .continueAfter(.milliseconds(200)))
        #expect(policy.decision(afterConsecutiveFailures: 3) == .stop)
    }
}
