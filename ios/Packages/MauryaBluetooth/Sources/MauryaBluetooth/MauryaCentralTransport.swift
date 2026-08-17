import CoreBluetooth
import Foundation
import MauryaProtocol

/// CoreBluetooth central transport for the Maurya FFE0/FFE1/FFE2 GATT profile.
///
/// CoreBluetooth objects and delegate callbacks remain confined to MainActor.
/// Protocol transactions are serialized by `BluetoothTransactionQueue`, which
/// never exposes CoreBluetooth reference types across its actor boundary.
@MainActor
public final class MauryaCentralTransport: NSObject {
    public let states: AsyncStream<BluetoothLifecycleState>
    public let discoveredDevices: AsyncStream<[DiscoveredMauryaDevice]>
    public let notifications: AsyncStream<Data>

    public private(set) var state: BluetoothLifecycleState = .idle
    public private(set) var availability: BluetoothAvailability = .unknown

    private let configuration: BluetoothTransportConfiguration
    private nonisolated let restorationEnabled: Bool
    private let stateContinuation: AsyncStream<BluetoothLifecycleState>.Continuation
    private let devicesContinuation: AsyncStream<[DiscoveredMauryaDevice]>.Continuation
    private let notificationContinuation: AsyncStream<Data>.Continuation
    private let ingressContinuation: AsyncStream<NotificationIngress>.Continuation

    private var central: CBCentralManager!
    private var stateMachine = BluetoothStateMachine()
    private var retainedPeripherals: [UUID: CBPeripheral] = [:]
    private var discovered: [UUID: DiscoveredMauryaDevice] = [:]
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var generationByPeripheral: [ObjectIdentifier: ConnectionGeneration] = [:]
    private var currentGeneration = ConnectionGeneration.initial
    private var reconnectAttempt = 0
    private var userRequestedDisconnect = false
    private var requestedScanScope: BluetoothScanScope?

    private var scanTimeoutTask: Task<Void, Never>?
    private var connectionPhaseTimeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var notificationPump: Task<Void, Never>?

    private var writeAcknowledgement: CheckedContinuation<Void, any Error>?
    private var writeAcknowledgementGeneration: ConnectionGeneration?
    private var writeAcknowledgementTimeoutTask: Task<Void, Never>?

    private var transactions: BluetoothTransactionQueue!

    public init(configuration: BluetoothTransportConfiguration = .init()) throws {
        self.configuration = configuration
        restorationEnabled = configuration.restorationIdentifier != nil

        let statePair = AsyncStream.makeStream(
            of: BluetoothLifecycleState.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        states = statePair.stream
        stateContinuation = statePair.continuation

        let devicePair = AsyncStream.makeStream(
            of: [DiscoveredMauryaDevice].self,
            bufferingPolicy: .bufferingNewest(8)
        )
        discoveredDevices = devicePair.stream
        devicesContinuation = devicePair.continuation

        let notificationPair = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingNewest(128)
        )
        notifications = notificationPair.stream
        notificationContinuation = notificationPair.continuation

        let ingressPair = AsyncStream.makeStream(
            of: NotificationIngress.self,
            bufferingPolicy: .bufferingOldest(256)
        )
        ingressContinuation = ingressPair.continuation

        super.init()

        transactions = try BluetoothTransactionQueue(
            maximumPendingCount: configuration.maximumPendingTransactions,
            writer: { [weak self] request, generation in
                guard let self else {
                    throw BluetoothFailure(.disconnected, detail: "BLE transport released")
                }
                try await self.writeRequest(request, generation: generation)
            }
        )

        let queue = transactions!
        notificationPump = Task(name: "Maurya BLE notification decoder") {
            for await ingress in ingressPair.stream {
                await queue.receive(ingress.bytes, generation: ingress.generation)
            }
        }

        var options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        if let restorationIdentifier = configuration.restorationIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = restorationIdentifier
        }
        central = CBCentralManager(delegate: self, queue: nil, options: options)
        stateContinuation.yield(state)
    }

    /// CoreBluetooth logs API misuse when an optional restoration callback is
    /// exposed without a restore identifier. Report the selector only for the
    /// configuration that actually opts into preservation/restoration.
    public nonisolated override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(CBCentralManagerDelegate.centralManager(_:willRestoreState:)) {
            return restorationEnabled
        }
        return super.responds(to: selector)
    }

    public func startScanning(scope: BluetoothScanScope = .foreground) throws {
        requestedScanScope = scope
        guard availability == .poweredOn else {
            transition(.availabilityChanged(availability))
            return
        }
        beginScan(scope: scope)
    }

    public func stopScanning() {
        requestedScanScope = nil
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        central.stopScan()
        if state == .scanning {
            transition(.scanStopped)
        }
    }

    /// Retrieves a known CoreBluetooth identifier before falling back to scan.
    public func connectKnownDevice(id: UUID) throws {
        if retainedPeripherals[id] == nil {
            retainedPeripherals[id] = central.retrievePeripherals(withIdentifiers: [id]).first
        }
        try connect(id: id)
    }

    public func connect(id: UUID) throws {
        guard availability == .poweredOn else {
            throw BluetoothFailure(.bluetoothUnavailable, detail: "Bluetooth is not powered on")
        }
        guard let peripheral = retainedPeripherals[id] else {
            throw BluetoothFailure(.deviceNotFound, detail: id.uuidString)
        }

        stopScanningIfNecessary()
        reconnectTask?.cancel()
        reconnectTask = nil
        userRequestedDisconnect = false
        currentGeneration = currentGeneration.advanced()
        generationByPeripheral[ObjectIdentifier(peripheral)] = currentGeneration
        activePeripheral = peripheral
        clearGattState()
        transition(.connectionRequested(deviceID: id, generation: currentGeneration))
        central.connect(peripheral, options: nil)
    }

    public func disconnect() {
        userRequestedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        guard let peripheral = activePeripheral else {
            transition(.reset)
            return
        }
        transition(.disconnectRequested(deviceID: peripheral.identifier, generation: currentGeneration))
        central.cancelPeripheralConnection(peripheral)
    }

    public func transact(
        _ request: Data,
        timeout: Duration? = nil
    ) async throws -> Data {
        guard case .ready(_, let generation) = state,
            generation == currentGeneration
        else {
            throw BluetoothFailure(.notReady, detail: "FFE2 notifications are not ready")
        }
        return try await transactions.transact(
            request,
            generation: generation,
            timeout: timeout ?? configuration.defaultResponseTimeout
        )
    }

    /// Explicit lifecycle teardown. The app owns when streams finish; state
    /// restoration is intentionally not represented as guaranteed execution.
    public func close() async {
        requestedScanScope = nil
        scanTimeoutTask?.cancel()
        connectionPhaseTimeoutTask?.cancel()
        reconnectTask?.cancel()
        notificationPump?.cancel()
        writeAcknowledgementTimeoutTask?.cancel()
        central.stopScan()
        if let activePeripheral {
            central.cancelPeripheralConnection(activePeripheral)
        }
        finishWriteAcknowledgement(
            .failure(BluetoothFailure(.disconnected, detail: "Transport closed")),
            generation: writeAcknowledgementGeneration
        )
        ingressContinuation.finish()
        notificationContinuation.finish()
        devicesContinuation.finish()
        stateContinuation.finish()
        await transactions.close()
    }

    private func beginScan(scope: BluetoothScanScope) {
        if state != .idle {
            if state == .scanning { return }
            transition(.reset)
        }
        discovered.removeAll(keepingCapacity: true)
        devicesContinuation.yield([])
        transition(.scanRequested)

        let services: [CBUUID]? = scope == .background ? [Self.serviceUUID] : nil
        central.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task(name: "Maurya BLE scan timeout") { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: self.configuration.scanTimeout)
                guard self.state == .scanning else { return }
                self.stopScanning()
            } catch {
                // Cancellation is the normal stop/connect path.
            }
        }
    }

    private func stopScanningIfNecessary() {
        requestedScanScope = nil
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        central.stopScan()
        if state == .scanning { transition(.scanStopped) }
    }

    private func transition(_ event: BluetoothLifecycleEvent) {
        do {
            guard try stateMachine.apply(event) else { return }
            state = stateMachine.state
            stateContinuation.yield(state)
            updateConnectionPhaseTimeout()
        } catch let failure as BluetoothFailure {
            state = .failed(failure)
            stateContinuation.yield(state)
            updateConnectionPhaseTimeout()
        } catch {
            let failure = BluetoothFailure(.invalidTransition, detail: String(describing: error))
            state = .failed(failure)
            stateContinuation.yield(state)
            updateConnectionPhaseTimeout()
        }
    }

    private func updateConnectionPhaseTimeout() {
        connectionPhaseTimeoutTask?.cancel()
        connectionPhaseTimeoutTask = nil

        let expectedState = state
        switch expectedState {
        case .connecting, .discoveringServices, .discoveringCharacteristics, .subscribing:
            connectionPhaseTimeoutTask = Task(name: "Maurya BLE connection phase timeout") { [weak self] in
                do {
                    guard let self else { return }
                    try await Task.sleep(for: self.configuration.connectionPhaseTimeout)
                    guard self.state == expectedState else { return }
                    self.fail(
                        .connectionFailed,
                        detail: "Connection phase timed out while in \(expectedState)"
                    )
                    if let peripheral = self.activePeripheral {
                        self.central.cancelPeripheralConnection(peripheral)
                    }
                } catch {
                    // A successful transition or explicit teardown cancelled it.
                }
            }
        case .idle, .waitingForBluetooth, .scanning, .ready, .disconnecting,
            .reconnectBackoff, .failed:
            break
        }
    }

    private func accept(_ peripheral: CBPeripheral) -> ConnectionGeneration? {
        guard peripheral === activePeripheral,
            let generation = generationByPeripheral[ObjectIdentifier(peripheral)],
            generation == currentGeneration
        else {
            return nil
        }
        return generation
    }

    private func fail(_ code: BluetoothFailure.Code, detail: String) {
        let failure = BluetoothFailure(code, detail: detail)
        transition(.failed(failure))
        finishWriteAcknowledgement(.failure(failure), generation: writeAcknowledgementGeneration)
    }

    private func clearGattState() {
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }

    private func writeRequest(
        _ request: Data,
        generation: ConnectionGeneration
    ) async throws {
        guard case .ready(_, generation) = state,
            let peripheral = activePeripheral,
            let characteristic = writeCharacteristic,
            characteristic.properties.contains(.write)
        else {
            throw BluetoothFailure(.notReady, detail: "FFE1 write-with-response is unavailable")
        }

        let maximumLength = peripheral.maximumWriteValueLength(for: .withResponse)
        let chunks = try WriteFragmenter.chunks(for: request, maximumLength: maximumLength)
        for chunk in chunks {
            try Task.checkCancellation()
            try await writeChunk(
                chunk,
                characteristic: characteristic,
                peripheral: peripheral,
                generation: generation
            )
        }
    }

    private func writeChunk(
        _ chunk: Data,
        characteristic: CBCharacteristic,
        peripheral: CBPeripheral,
        generation: ConnectionGeneration
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard writeAcknowledgement == nil else {
                    continuation.resume(
                        throwing: BluetoothFailure(.writeFailed, detail: "A chunk acknowledgement is already pending")
                    )
                    return
                }
                writeAcknowledgement = continuation
                writeAcknowledgementGeneration = generation
                writeAcknowledgementTimeoutTask = Task(name: "Maurya BLE write acknowledgement timeout") { [weak self] in
                    do {
                        guard let self else { return }
                        try await Task.sleep(for: self.configuration.writeAcknowledgementTimeout)
                        self.finishWriteAcknowledgement(
                            .failure(BluetoothFailure(.writeFailed, detail: "FFE1 write acknowledgement timed out")),
                            generation: generation
                        )
                    } catch {
                        // Callback completion or cancellation owns cleanup.
                    }
                }
                peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishWriteAcknowledgement(
                    .failure(CancellationError()),
                    generation: generation
                )
            }
        }
    }

    private func finishWriteAcknowledgement(
        _ result: Result<Void, any Error>,
        generation: ConnectionGeneration?
    ) {
        guard generation == writeAcknowledgementGeneration,
            let continuation = writeAcknowledgement
        else { return }
        writeAcknowledgement = nil
        writeAcknowledgementGeneration = nil
        writeAcknowledgementTimeoutTask?.cancel()
        writeAcknowledgementTimeoutTask = nil
        continuation.resume(with: result)
    }

    private func handleDisconnect(_ peripheral: CBPeripheral, error: (any Error)?) {
        guard let generation = accept(peripheral) else { return }
        clearGattState()
        finishWriteAcknowledgement(
            .failure(BluetoothFailure(.disconnected, detail: error.map(String.init(describing:)) ?? "Disconnected")),
            generation: generation
        )
        Task { await transactions.invalidate(generation: generation, error: .init(.disconnected)) }

        if userRequestedDisconnect || availability != .poweredOn {
            transition(.disconnected(deviceID: peripheral.identifier, generation: generation))
            activePeripheral = nil
            return
        }
        scheduleReconnect(peripheral: peripheral, generation: generation)
    }

    private func scheduleReconnect(
        peripheral: CBPeripheral,
        generation: ConnectionGeneration
    ) {
        reconnectAttempt += 1
        let delay = configuration.reconnectPolicy.delay(forAttempt: reconnectAttempt)
        transition(
            .reconnectScheduled(
                deviceID: peripheral.identifier,
                generation: generation,
                attempt: reconnectAttempt,
                delay: delay
            )
        )
        reconnectTask?.cancel()
        reconnectTask = Task(name: "Maurya BLE reconnect \(reconnectAttempt)") { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self,
                    self.userRequestedDisconnect == false,
                    self.availability == .poweredOn,
                    self.activePeripheral === peripheral
                else { return }
                try self.connect(id: peripheral.identifier)
            } catch is CancellationError {
                // User disconnect, close, or a newer attempt cancelled this one.
            } catch {
                guard let self else { return }
                self.scheduleReconnect(peripheral: peripheral, generation: generation)
            }
        }
    }

    private static let serviceUUID = CBUUID(string: MauryaBluetoothUUID.service)
    private static let writeUUID = CBUUID(string: MauryaBluetoothUUID.writeCharacteristic)
    private static let notifyUUID = CBUUID(string: MauryaBluetoothUUID.notifyCharacteristic)
}

private struct NotificationIngress: Sendable {
    let bytes: Data
    let generation: ConnectionGeneration
}

extension MauryaCentralTransport: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        availability = BluetoothAvailability(central.state)
        transition(.availabilityChanged(availability))

        if availability == .poweredOn, let requestedScanScope {
            beginScan(scope: requestedScanScope)
        } else if availability != .poweredOn {
            scanTimeoutTask?.cancel()
            central.stopScan()
            if let peripheral = activePeripheral {
                handleDisconnect(peripheral, error: nil)
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let advertisesService = serviceUUIDs.contains(Self.serviceUUID)
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Maurya"
        guard
            BluetoothAdvertisementMatcher.matches(
                filterMaurya: true,
                name: advertisedName ?? peripheral.name,
                advertisedServiceUUIDs: serviceUUIDs.map(\.uuidString)
            )
        else { return }

        retainedPeripherals[peripheral.identifier] = peripheral
        discovered[peripheral.identifier] = DiscoveredMauryaDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisesMauryaService: advertisesService,
            lastSeen: .now
        )
        devicesContinuation.yield(
            discovered.values.sorted { lhs, rhs in
                lhs.rssi == rhs.rssi ? lhs.id.uuidString < rhs.id.uuidString : lhs.rssi > rhs.rssi
            }
        )
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let generation = accept(peripheral),
            state == .connecting(deviceID: peripheral.identifier, generation: generation)
        else { return }
        reconnectAttempt = 0
        peripheral.delegate = self
        transition(.connected(deviceID: peripheral.identifier, generation: generation))
        peripheral.discoverServices([Self.serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard let generation = accept(peripheral) else { return }
        if userRequestedDisconnect {
            transition(.disconnected(deviceID: peripheral.identifier, generation: generation))
        } else {
            scheduleReconnect(peripheral: peripheral, generation: generation)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: (any Error)?
    ) {
        if isReconnecting { return }
        handleDisconnect(peripheral, error: error)
    }

    public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals {
            peripheral.delegate = self
            retainedPeripherals[peripheral.identifier] = peripheral
        }
        guard let peripheral = peripherals.first(where: { $0.state == .connected }) else { return }
        currentGeneration = currentGeneration.advanced()
        generationByPeripheral[ObjectIdentifier(peripheral)] = currentGeneration
        activePeripheral = peripheral
        transition(.connectionRequested(deviceID: peripheral.identifier, generation: currentGeneration))
        transition(.connected(deviceID: peripheral.identifier, generation: currentGeneration))
        peripheral.discoverServices([Self.serviceUUID])
    }
}

extension MauryaCentralTransport: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let generation = accept(peripheral),
            state == .discoveringServices(deviceID: peripheral.identifier, generation: generation)
        else { return }
        if let error {
            fail(.connectionFailed, detail: String(describing: error))
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail(.serviceMissing, detail: MauryaBluetoothUUID.service)
            central.cancelPeripheralConnection(peripheral)
            return
        }
        transition(.serviceDiscovered(deviceID: peripheral.identifier, generation: generation))
        peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard let generation = accept(peripheral),
            state == .discoveringCharacteristics(deviceID: peripheral.identifier, generation: generation)
        else { return }
        if let error {
            fail(.connectionFailed, detail: String(describing: error))
            central.cancelPeripheralConnection(peripheral)
            return
        }

        let characteristics = service.characteristics ?? []
        guard let write = characteristics.first(where: { $0.uuid == Self.writeUUID }),
            write.properties.contains(.write),
            let notify = characteristics.first(where: { $0.uuid == Self.notifyUUID }),
            notify.properties.contains(.notify) || notify.properties.contains(.indicate)
        else {
            fail(.characteristicMissing, detail: "FFE1 write or FFE2 notify")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        writeCharacteristic = write
        notifyCharacteristic = notify
        transition(.characteristicsDiscovered(deviceID: peripheral.identifier, generation: generation))
        peripheral.setNotifyValue(true, for: notify)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let generation = accept(peripheral),
            characteristic.uuid == Self.notifyUUID,
            state == .subscribing(deviceID: peripheral.identifier, generation: generation)
        else { return }
        guard error == nil, characteristic.isNotifying else {
            fail(
                .notificationSubscriptionFailed,
                detail: error.map(String.init(describing:)) ?? "FFE2 did not enter notifying state"
            )
            central.cancelPeripheralConnection(peripheral)
            return
        }
        transition(.notificationsEnabled(deviceID: peripheral.identifier, generation: generation))
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let generation = accept(peripheral),
            characteristic.uuid == Self.notifyUUID,
            error == nil,
            let bytes = characteristic.value,
            bytes.isEmpty == false
        else { return }
        notificationContinuation.yield(bytes)
        ingressContinuation.yield(.init(bytes: bytes, generation: generation))
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let generation = accept(peripheral), characteristic.uuid == Self.writeUUID else { return }
        if let error {
            finishWriteAcknowledgement(.failure(error), generation: generation)
        } else {
            finishWriteAcknowledgement(.success(()), generation: generation)
        }
    }
}

private extension BluetoothAvailability {
    init(_ state: CBManagerState) {
        switch state {
        case .unknown: self = .unknown
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        @unknown default: self = .unknown
        }
    }
}
