import Foundation
import MauryaProtocol

public protocol DeviceTransport: Sendable {
    func transact(_ request: Data, timeout: Duration) async throws -> Data
}

public actor DeviceRepository {
    private let transport: any DeviceTransport
    private let responseTimeout: Duration
    private var unitID: UInt8
    private var connectionGeneration: UInt64 = 0
    private var currentState: DeviceRepositoryState

    public init(
        transport: any DeviceTransport,
        unitID: UInt8 = DeviceRegisterMap.defaultDeviceAddress,
        responseTimeout: Duration = .seconds(2),
        initiallyConnected: Bool = true
    ) {
        self.transport = transport
        self.unitID = unitID
        self.responseTimeout = responseTimeout
        self.currentState = DeviceRepositoryState(isConnected: initiallyConnected)
    }

    public func state() -> DeviceRepositoryState {
        currentState
    }

    public func markConnected(unitID: UInt8? = nil) {
        connectionGeneration &+= 1
        if let unitID { self.unitID = unitID }
        currentState.isConnected = true
        currentState.freshness = currentState.snapshot == nil ? .stale : .current
    }

    /// Invalidates in-flight work while retaining the last snapshot as explicitly stale.
    public func markDisconnected() {
        connectionGeneration &+= 1
        currentState.isConnected = false
        currentState.freshness = .stale
    }

    public func refreshSnapshot() async throws -> DeviceSnapshot {
        let generation = try beginOperation()
        currentState.freshness = .pending
        do {
            let reads = try DeviceRegisterBatcher.snapshotReads()
            let configuration = try await read(reads[0], generation: generation)
            let groups = try await read(reads[1], generation: generation)
            try validate(generation: generation)
            let snapshot = try DeviceMapper.snapshot(configuration: configuration, groupRegisters: groups)
            currentState.snapshot = snapshot
            currentState.freshness = .current
            return snapshot
        } catch {
            throw handle(error, generation: generation)
        }
    }

    public func refreshTelemetry() async throws -> DeviceDiagnostics {
        let generation = try beginOperation()
        do {
            let batch = try RegisterReadBatch(
                startRegister: DeviceRegisterMap.temperatureCelsiusTimes100,
                count: 2
            )
            let values = try await read(batch, generation: generation)
            try validate(generation: generation)
            var diagnostics = currentState.snapshot?.diagnostics ?? DeviceDiagnostics()
            diagnostics.temperatureCelsiusTimes100 = Int16(bitPattern: values[0])
            diagnostics.vddaMillivolts = values[1]
            return diagnostics
        } catch {
            throw handle(error, generation: generation)
        }
    }

    public func fetchDeviceInfo() async throws -> DeviceInfo {
        let generation = try beginOperation()
        do {
            let response = try await transact(
                try DeviceInfoCodec.request(unitID: unitID),
                generation: generation
            )
            return try DeviceInfoCodec.decodeResponse(response, expectedUnitID: unitID)
        } catch {
            throw handle(error, generation: generation)
        }
    }

    public func applyScene(_ state: DeviceGlobalState) async throws {
        try await write(try DeviceRegisterBatcher.sceneWrite(state))
    }

    public func applyGlobalLED(_ state: DeviceGlobalState) async throws {
        try await write(try DeviceRegisterBatcher.globalLEDWrite(state))
    }

    public func applyGroup(index: Int, state: DeviceGroupState) async throws {
        try await write(try DeviceRegisterBatcher.groupWrite(index: index, state: state))
    }

    public func applyAllGroups(_ groups: [DeviceGroupState]) async throws {
        let generation = try beginOperation()
        currentState.freshness = .pending
        do {
            for batch in try DeviceRegisterBatcher.allGroupsWrite(groups) {
                try await write(batch, generation: generation)
            }
            try validate(generation: generation)
            currentState.freshness = .current
        } catch {
            throw handle(error, generation: generation)
        }
    }

    public func clearDiagnostics() async throws {
        let generation = try beginOperation()
        do {
            let request = ModbusRequest.writeSingleRegister(
                unitID: unitID,
                register: DeviceRegisterMap.parseErrorCount,
                value: DeviceRegisterMap.diagnosticClearKey
            )
            let response = try await transact(request, generation: generation)
            guard
                case .writeSingleAcknowledgement(
                    let responseUnitID,
                    DeviceRegisterMap.parseErrorCount,
                    DeviceRegisterMap.diagnosticClearKey
                ) = try ModbusResponseCodec.decode(response, expectedUnitID: unitID),
                responseUnitID == unitID
            else {
                throw DeviceFailure(.protocolViolation, detail: "Unexpected diagnostic-clear acknowledgement")
            }
        } catch {
            throw handle(error, generation: generation)
        }
    }

    /// Structured polling: the caller owns this task and cancellation propagates normally.
    public func runPolling(
        policy: DevicePollingPolicy,
        sleep: @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) async throws {
        var failures = 0
        while true {
            try Task.checkCancellation()
            do {
                _ = try await refreshSnapshot()
                failures = 0
            } catch let failure as DeviceFailure where failure.isRetryable {
                failures += 1
            }

            switch policy.decision(afterConsecutiveFailures: failures) {
            case .continueAfter(let delay):
                try await sleep(delay)
            case .stop:
                return
            }
        }
    }

    private func write(_ batch: RegisterWriteBatch) async throws {
        let generation = try beginOperation()
        currentState.freshness = .pending
        do {
            try await write(batch, generation: generation)
            try validate(generation: generation)
            currentState.freshness = .current
        } catch {
            throw handle(error, generation: generation)
        }
    }

    private func write(_ batch: RegisterWriteBatch, generation: UInt64) async throws {
        let request = try ModbusRequest.writeMultipleRegisters(
            unitID: unitID,
            startRegister: batch.startRegister,
            values: batch.values
        )
        let response = try await transact(request, generation: generation)
        switch try ModbusResponseCodec.decode(response, expectedUnitID: unitID) {
        case .writeMultipleAcknowledgement(
            _, startRegister: batch.startRegister, quantity: UInt16(batch.values.count)
        ):
            return
        case .exception(_, _, let code):
            throw DeviceFailure(.deviceRejected, detail: "Modbus exception \(code)")
        default:
            throw DeviceFailure(.protocolViolation, detail: "Unexpected write acknowledgement")
        }
    }

    private func read(_ batch: RegisterReadBatch, generation: UInt64) async throws -> [UInt16] {
        let request = try ModbusRequest.readHoldingRegisters(
            unitID: unitID,
            startRegister: batch.startRegister,
            quantity: batch.count
        )
        let response = try await transact(request, generation: generation)
        switch try ModbusResponseCodec.decode(response, expectedUnitID: unitID) {
        case .readHoldingRegisters(_, let values) where values.count == batch.count:
            return values
        case .exception(_, _, let code):
            throw DeviceFailure(.deviceRejected, detail: "Modbus exception \(code)")
        default:
            throw DeviceFailure(.protocolViolation, detail: "Unexpected read response")
        }
    }

    private func transact(_ request: Data, generation: UInt64) async throws -> Data {
        try validate(generation: generation)
        let response = try await transport.transact(request, timeout: responseTimeout)
        try validate(generation: generation)
        return response
    }

    private func beginOperation() throws -> UInt64 {
        guard currentState.isConnected else {
            throw DeviceFailure(.disconnected, detail: "Device is not connected")
        }
        return connectionGeneration
    }

    private func validate(generation: UInt64) throws {
        guard generation == connectionGeneration, currentState.isConnected else {
            throw DeviceFailure(.disconnected, detail: "Connection changed during operation")
        }
    }

    private func handle(_ error: any Error, generation: UInt64) -> DeviceFailure {
        let failure = DeviceFailureClassifier.classify(error)
        if generation == connectionGeneration, currentState.isConnected {
            currentState.freshness = .failed(failure)
        } else {
            currentState.freshness = .stale
        }
        return failure
    }
}
