import Foundation
import Testing

@testable import MauryaBluetooth

struct BluetoothStateMachineTests {
    @Test("FFE0 discovery reaches ready only after FFE2 subscription")
    func fullReadyPath() throws {
        let deviceID = UUID()
        let generation = ConnectionGeneration(rawValue: 1)
        var machine = BluetoothStateMachine()

        try machine.apply(.scanRequested)
        try machine.apply(.connectionRequested(deviceID: deviceID, generation: generation))
        #expect(machine.state == .connecting(deviceID: deviceID, generation: generation))

        try machine.apply(.connected(deviceID: deviceID, generation: generation))
        #expect(machine.state == .discoveringServices(deviceID: deviceID, generation: generation))

        try machine.apply(.serviceDiscovered(deviceID: deviceID, generation: generation))
        #expect(machine.state == .discoveringCharacteristics(deviceID: deviceID, generation: generation))

        try machine.apply(.characteristicsDiscovered(deviceID: deviceID, generation: generation))
        #expect(machine.state == .subscribing(deviceID: deviceID, generation: generation))

        try machine.apply(.notificationsEnabled(deviceID: deviceID, generation: generation))
        #expect(machine.state == .ready(deviceID: deviceID, generation: generation))
    }

    @Test("Impossible transitions are rejected")
    func invalidTransition() {
        let deviceID = UUID()
        var machine = BluetoothStateMachine()

        do {
            try machine.apply(
                .connected(deviceID: deviceID, generation: .init(rawValue: 1))
            )
            Issue.record("Idle must not transition directly to service discovery")
        } catch let failure as BluetoothFailure {
            #expect(failure.code == .invalidTransition)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Events from an older connection generation are ignored")
    func staleGenerationIsIgnored() throws {
        let deviceID = UUID()
        let first = ConnectionGeneration(rawValue: 1)
        let second = ConnectionGeneration(rawValue: 2)
        var machine = BluetoothStateMachine()

        try machine.apply(.connectionRequested(deviceID: deviceID, generation: first))
        try machine.apply(.disconnected(deviceID: deviceID, generation: first))
        try machine.apply(
            .reconnectScheduled(
                deviceID: deviceID,
                generation: first,
                attempt: 1,
                delay: .seconds(1)
            )
        )
        try machine.apply(.connectionRequested(deviceID: deviceID, generation: second))

        let accepted = try machine.apply(.connected(deviceID: deviceID, generation: first))
        #expect(accepted == false)
        #expect(machine.state == .connecting(deviceID: deviceID, generation: second))
        #expect(machine.latestGeneration == second)
    }

    @Test("A user disconnect has an explicit disconnecting path")
    func userDisconnectPath() throws {
        let deviceID = UUID()
        let generation = ConnectionGeneration(rawValue: 4)
        var machine = BluetoothStateMachine()
        try makeReady(&machine, deviceID: deviceID, generation: generation)

        try machine.apply(.disconnectRequested(deviceID: deviceID, generation: generation))
        #expect(machine.state == .disconnecting(deviceID: deviceID, generation: generation))
        try machine.apply(.disconnected(deviceID: deviceID, generation: generation))
        #expect(machine.state == .idle)
    }

    private func makeReady(
        _ machine: inout BluetoothStateMachine,
        deviceID: UUID,
        generation: ConnectionGeneration
    ) throws {
        try machine.apply(.connectionRequested(deviceID: deviceID, generation: generation))
        try machine.apply(.connected(deviceID: deviceID, generation: generation))
        try machine.apply(.serviceDiscovered(deviceID: deviceID, generation: generation))
        try machine.apply(.characteristicsDiscovered(deviceID: deviceID, generation: generation))
        try machine.apply(.notificationsEnabled(deviceID: deviceID, generation: generation))
    }
}
