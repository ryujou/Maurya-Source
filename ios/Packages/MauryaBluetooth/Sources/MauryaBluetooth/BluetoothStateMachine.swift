import Foundation

public enum BluetoothLifecycleEvent: Sendable, Equatable {
    case availabilityChanged(BluetoothAvailability)
    case scanRequested
    case scanStopped
    case connectionRequested(deviceID: UUID, generation: ConnectionGeneration)
    case connected(deviceID: UUID, generation: ConnectionGeneration)
    case serviceDiscovered(deviceID: UUID, generation: ConnectionGeneration)
    case characteristicsDiscovered(deviceID: UUID, generation: ConnectionGeneration)
    case notificationsEnabled(deviceID: UUID, generation: ConnectionGeneration)
    case disconnectRequested(deviceID: UUID, generation: ConnectionGeneration)
    case disconnected(deviceID: UUID, generation: ConnectionGeneration)
    case reconnectScheduled(
        deviceID: UUID,
        generation: ConnectionGeneration,
        attempt: Int,
        delay: Duration
    )
    case failed(BluetoothFailure)
    case reset
}

/// Pure lifecycle reducer. Delegate events carry a connection generation; an
/// event from an older attempt is ignored instead of corrupting the new state.
public struct BluetoothStateMachine: Sendable {
    public private(set) var state: BluetoothLifecycleState
    public private(set) var latestGeneration: ConnectionGeneration

    public init(
        state: BluetoothLifecycleState = .idle,
        latestGeneration: ConnectionGeneration = .initial
    ) {
        self.state = state
        self.latestGeneration = latestGeneration
    }

    @discardableResult
    public mutating func apply(_ event: BluetoothLifecycleEvent) throws -> Bool {
        if let eventGeneration = event.generation,
            eventGeneration < latestGeneration
        {
            return false
        }

        switch event {
        case .availabilityChanged(let availability):
            switch availability {
            case .poweredOn:
                if case .waitingForBluetooth = state { state = .idle }
            default:
                state = .waitingForBluetooth(availability)
            }

        case .scanRequested:
            guard state == .idle else { throw invalid(event) }
            state = .scanning

        case .scanStopped:
            guard state == .scanning else { throw invalid(event) }
            state = .idle

        case let .connectionRequested(deviceID, generation):
            guard state == .idle || state == .scanning || isReconnectState else {
                throw invalid(event)
            }
            guard generation > latestGeneration || latestGeneration == .initial else {
                return false
            }
            latestGeneration = generation
            state = .connecting(deviceID: deviceID, generation: generation)

        case let .connected(deviceID, generation):
            guard state == .connecting(deviceID: deviceID, generation: generation) else {
                throw invalid(event)
            }
            state = .discoveringServices(deviceID: deviceID, generation: generation)

        case let .serviceDiscovered(deviceID, generation):
            guard state == .discoveringServices(deviceID: deviceID, generation: generation) else {
                throw invalid(event)
            }
            state = .discoveringCharacteristics(deviceID: deviceID, generation: generation)

        case let .characteristicsDiscovered(deviceID, generation):
            guard state == .discoveringCharacteristics(deviceID: deviceID, generation: generation) else {
                throw invalid(event)
            }
            state = .subscribing(deviceID: deviceID, generation: generation)

        case let .notificationsEnabled(deviceID, generation):
            guard state == .subscribing(deviceID: deviceID, generation: generation) else {
                throw invalid(event)
            }
            state = .ready(deviceID: deviceID, generation: generation)

        case let .disconnectRequested(deviceID, generation):
            guard state.generation == generation else { return false }
            state = .disconnecting(deviceID: deviceID, generation: generation)

        case let .disconnected(_, generation):
            guard state.generation == generation else { return false }
            state = .idle

        case let .reconnectScheduled(deviceID, generation, attempt, delay):
            guard generation >= latestGeneration else { return false }
            state = .reconnectBackoff(
                deviceID: deviceID,
                generation: generation,
                attempt: attempt,
                delay: delay
            )

        case .failed(let failure):
            state = .failed(failure)

        case .reset:
            state = .idle
        }
        return true
    }

    private var isReconnectState: Bool {
        if case .reconnectBackoff = state { return true }
        return false
    }

    private func invalid(_ event: BluetoothLifecycleEvent) -> BluetoothFailure {
        BluetoothFailure(
            .invalidTransition,
            detail: "Cannot apply \(event) while in \(state)"
        )
    }
}

private extension BluetoothLifecycleEvent {
    var generation: ConnectionGeneration? {
        switch self {
        case .connectionRequested(_, let generation),
            .connected(_, let generation),
            .serviceDiscovered(_, let generation),
            .characteristicsDiscovered(_, let generation),
            .notificationsEnabled(_, let generation),
            .disconnectRequested(_, let generation),
            .disconnected(_, let generation),
            .reconnectScheduled(_, let generation, _, _):
            generation
        case .availabilityChanged, .scanRequested, .scanStopped, .failed, .reset:
            nil
        }
    }
}
