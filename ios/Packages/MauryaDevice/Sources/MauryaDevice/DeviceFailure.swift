import MauryaBluetooth
import MauryaProtocol

public struct DeviceFailure: Error, Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case cancelled
        case disconnected
        case unavailable
        case timeout
        case queueSaturated
        case protocolViolation
        case deviceRejected
        case invalidState
        case transport
    }

    public let category: Category
    public let detail: String

    public init(_ category: Category, detail: String = "") {
        self.category = category
        self.detail = detail
    }

    public var isRetryable: Bool {
        switch category {
        case .timeout, .queueSaturated, .transport:
            true
        case .cancelled, .disconnected, .unavailable, .protocolViolation,
            .deviceRejected, .invalidState:
            false
        }
    }
}

public enum DeviceFailureClassifier {
    public static func classify(_ error: any Error) -> DeviceFailure {
        if error is CancellationError {
            return DeviceFailure(.cancelled)
        }
        if let failure = error as? DeviceFailure {
            return failure
        }
        if let failure = error as? BluetoothFailure {
            let category: DeviceFailure.Category
            switch failure.code {
            case .disconnected, .staleConnection, .notReady:
                category = .disconnected
            case .bluetoothUnavailable, .permissionDenied:
                category = .unavailable
            case .responseTimeout:
                category = .timeout
            case .queueFull:
                category = .queueSaturated
            case .protocolDecodeFailed:
                category = .protocolViolation
            case .invalidTransition:
                category = .invalidState
            case .deviceNotFound, .connectionFailed, .serviceMissing,
                .characteristicMissing, .notificationSubscriptionFailed,
                .writeUnsupported, .writeFailed:
                category = .transport
            }
            return DeviceFailure(category, detail: failure.detail)
        }
        if error is ModbusError || error is VendorProtocolError || error is DeviceInfoError
            || error is DeviceMappingError
        {
            return DeviceFailure(.protocolViolation, detail: String(describing: error))
        }
        return DeviceFailure(.transport, detail: String(describing: error))
    }
}
