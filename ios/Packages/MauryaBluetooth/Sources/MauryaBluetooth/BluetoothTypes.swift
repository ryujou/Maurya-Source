import Foundation

public enum BluetoothAvailability: String, Sendable, Equatable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum BluetoothScanScope: Sendable, Equatable {
    /// Discovers devices that omit FFE0 from their advertisement and applies
    /// Maurya name/service filtering in the app.
    case foreground

    /// Uses an FFE0-filtered scan, as required for background discovery.
    case background
}

public struct DiscoveredMauryaDevice: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let advertisesMauryaService: Bool
    public let lastSeen: ContinuousClock.Instant

    public init(
        id: UUID,
        name: String,
        rssi: Int,
        advertisesMauryaService: Bool,
        lastSeen: ContinuousClock.Instant
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisesMauryaService = advertisesMauryaService
        self.lastSeen = lastSeen
    }
}

public struct ConnectionGeneration: RawRepresentable, Sendable, Hashable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = ConnectionGeneration(rawValue: 0)

    public func advanced() -> Self {
        .init(rawValue: rawValue == .max ? 1 : rawValue + 1)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum BluetoothLifecycleState: Sendable, Equatable {
    case idle
    case waitingForBluetooth(BluetoothAvailability)
    case scanning
    case connecting(deviceID: UUID, generation: ConnectionGeneration)
    case discoveringServices(deviceID: UUID, generation: ConnectionGeneration)
    case discoveringCharacteristics(deviceID: UUID, generation: ConnectionGeneration)
    case subscribing(deviceID: UUID, generation: ConnectionGeneration)
    case ready(deviceID: UUID, generation: ConnectionGeneration)
    case disconnecting(deviceID: UUID, generation: ConnectionGeneration)
    case reconnectBackoff(
        deviceID: UUID,
        generation: ConnectionGeneration,
        attempt: Int,
        delay: Duration
    )
    case failed(BluetoothFailure)

    public var generation: ConnectionGeneration? {
        switch self {
        case .connecting(_, let generation),
            .discoveringServices(_, let generation),
            .discoveringCharacteristics(_, let generation),
            .subscribing(_, let generation),
            .ready(_, let generation),
            .disconnecting(_, let generation),
            .reconnectBackoff(_, let generation, _, _):
            generation
        case .idle, .waitingForBluetooth, .scanning, .failed:
            nil
        }
    }
}

public struct BluetoothFailure: Error, Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case bluetoothUnavailable
        case permissionDenied
        case invalidTransition
        case deviceNotFound
        case connectionFailed
        case serviceMissing
        case characteristicMissing
        case notificationSubscriptionFailed
        case notReady
        case writeUnsupported
        case writeFailed
        case responseTimeout
        case queueFull
        case disconnected
        case protocolDecodeFailed
        case staleConnection
    }

    public let code: Code
    public let detail: String

    public init(_ code: Code, detail: String = "") {
        self.code = code
        self.detail = detail
    }
}

public struct BluetoothTransportConfiguration: Sendable, Equatable {
    public var maximumPendingTransactions: Int
    public var defaultResponseTimeout: Duration
    public var writeAcknowledgementTimeout: Duration
    public var connectionPhaseTimeout: Duration
    public var scanTimeout: Duration
    public var reconnectPolicy: ReconnectBackoffPolicy
    public var restorationIdentifier: String?

    public init(
        maximumPendingTransactions: Int = 32,
        defaultResponseTimeout: Duration = .seconds(2),
        writeAcknowledgementTimeout: Duration = .seconds(2),
        connectionPhaseTimeout: Duration = .seconds(10),
        scanTimeout: Duration = .seconds(15),
        reconnectPolicy: ReconnectBackoffPolicy = .init(),
        restorationIdentifier: String? = nil
    ) {
        precondition(maximumPendingTransactions > 0)
        self.maximumPendingTransactions = maximumPendingTransactions
        self.defaultResponseTimeout = defaultResponseTimeout
        self.writeAcknowledgementTimeout = writeAcknowledgementTimeout
        self.connectionPhaseTimeout = connectionPhaseTimeout
        self.scanTimeout = scanTimeout
        self.reconnectPolicy = reconnectPolicy
        self.restorationIdentifier = restorationIdentifier
    }
}
