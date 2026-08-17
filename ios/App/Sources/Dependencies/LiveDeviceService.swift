import Foundation
import MauryaBluetooth
import MauryaDevice
import MauryaEffects
import MauryaOTA
import MauryaPlayback
import MauryaProtocol
import Observation

@MainActor
@Observable
final class LiveDeviceService: DeviceDiscoveryService, DeviceControlService {
    typealias TransportFactory = @MainActor () throws -> any BluetoothTransporting
    typealias RepositoryFactory = @MainActor (any DeviceTransport) -> any DeviceRepositoryServing
    typealias TelemetrySleeper = @Sendable (Duration) async throws -> Void

    private(set) var scanState = ScanPresentationState.idle
    private(set) var devices: [ScanDevice] = []
    private(set) var connectionState = BluetoothLifecycleState.idle
    private(set) var snapshot: DeviceSnapshot?
    private(set) var deviceInfo: DeviceInfo?
    private(set) var operationError: String?
    private(set) var operationMessageKey: String?
    private(set) var isPerformingAction = false
    private(set) var isRefreshing = false

    private let transportFactory: TransportFactory
    private var transport: (any BluetoothTransporting)?
    private var repository: (any DeviceRepositoryServing)?
    private var selectedDeviceID: UUID?
    private let repositoryFactory: RepositoryFactory
    private let telemetrySleeper: TelemetrySleeper
    private var stateTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var scanAfterDisconnect = false

    init(
        transportFactory: @escaping TransportFactory = {
            try MauryaCentralTransport(configuration: BluetoothTransportConfiguration())
        },
        repositoryFactory: @escaping RepositoryFactory = { DeviceRepository(transport: $0, initiallyConnected: false) },
        telemetrySleeper: @escaping TelemetrySleeper = { try await Task.sleep(for: $0) }
    ) {
        self.transportFactory = transportFactory
        self.repositoryFactory = repositoryFactory
        self.telemetrySleeper = telemetrySleeper
    }

    func startScanning() {
        do {
            let transport = try prepareTransport()
            try transport.startScanning(scope: .foreground)
        } catch {
            scanState = .failed(message: String(describing: error))
        }
    }

    func stopScanning() {
        guard transport?.state == .scanning else { return }
        transport?.stopScanning()
    }

    func returnToDeviceList() {
        guard let transport else {
            startScanning()
            return
        }
        switch transport.state {
        case .idle, .waitingForBluetooth, .scanning, .failed:
            scanAfterDisconnect = false
            startScanning()
        case .connecting, .discoveringServices, .discoveringCharacteristics,
            .subscribing, .ready, .disconnecting, .reconnectBackoff:
            scanAfterDisconnect = true
            transport.disconnect()
        }
    }

    func connect(to id: UUID) {
        do {
            let transport = try prepareTransport()
            selectedDeviceID = id
            try transport.connect(id: id)
        } catch {
            scanState = .failed(message: String(describing: error))
        }
    }

    func reconnect() {
        guard let selectedDeviceID else {
            operationError = "device.reconnect.unavailable"
            return
        }
        connect(to: selectedDeviceID)
    }

    func runTelemetryPolling() async {
        while Task.isCancelled == false {
            do {
                try await telemetrySleeper(.seconds(1))
                guard case .ready = connectionState,
                    let repository,
                    let current = snapshot
                else { return }
                let diagnostics = try await repository.refreshTelemetry()
                snapshot = try DeviceSnapshot(
                    global: current.global,
                    groups: current.groups,
                    diagnostics: diagnostics
                )
            } catch is CancellationError {
                return
            } catch {
                operationError = String(describing: error)
            }
        }
    }

    func refresh() async {
        guard let repository else {
            operationError = "integration.device.not-ready"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let refreshedSnapshot = repository.refreshSnapshot()
            async let refreshedInfo = repository.fetchDeviceInfo()
            snapshot = try await refreshedSnapshot
            deviceInfo = try await refreshedInfo
            operationError = nil
        } catch is CancellationError {
            return
        } catch {
            operationError = String(describing: error)
        }
    }

    func applyGroup(index: Int, state: DeviceGroupState) async {
        await performAction(successKey: "device.status.group.applied") { repository in
            try await repository.applyGroup(index: index, state: state)
        } verify: { refreshed in
            refreshed.groups.indices.contains(index) && refreshed.groups[index] == state
        }
    }

    func applyAllGroups(_ state: DeviceGroupState) async {
        await performAction(successKey: "device.status.groups.applied") { repository in
            try await repository.applyAllGroups(
                Array(repeating: state, count: DeviceRegisterMap.groupCount)
            )
        } verify: { refreshed in
            refreshed.groups.count == DeviceRegisterMap.groupCount
                && refreshed.groups.allSatisfy { $0 == state }
        }
    }

    func applyColorToAllGroups(hue: UInt16, saturation: UInt16, value: UInt16) async {
        guard let groups = snapshot?.groups,
            groups.count == DeviceRegisterMap.groupCount
        else {
            operationError = "integration.device.not-ready"
            return
        }
        let updated = groups.map {
            DeviceGroupState(
                mode: $0.mode,
                hue: hue,
                saturation: saturation,
                value: value,
                parameter: $0.parameter
            )
        }
        await performAction(successKey: "device.status.color.applied") { repository in
            try await repository.applyAllGroups(updated)
        } verify: { refreshed in
            refreshed.groups == updated
        }
    }

    func applyScene(_ state: DeviceGlobalState) async {
        await performAction(successKey: "device.status.scene.applied") { repository in
            try await repository.applyScene(state)
        } verify: { refreshed in
            refreshed.global.sceneMode == state.sceneMode
                && refreshed.global.sceneParameter == min(state.sceneParameter, 255)
        }
    }

    func applyGlobalLED(_ state: DeviceGlobalState) async {
        await performAction(successKey: "device.status.global.applied") { repository in
            try await repository.applyGlobalLED(state)
        } verify: { refreshed in
            refreshed.global.brightness == min(state.brightness, 255)
                && refreshed.global.redGain == min(state.redGain, 255)
                && refreshed.global.greenGain == min(state.greenGain, 255)
                && refreshed.global.blueGain == min(state.blueGain, 255)
        }
    }

    func clearDiagnostics() async {
        await performAction(successKey: "device.status.diagnostics.cleared") { repository in
            try await repository.clearDiagnostics()
        }
    }

    /// Runs only from the explicit physical-validation UI-test launch argument.
    /// It snapshots every writable lighting register, exercises the Android-equivalent
    /// write paths, and restores the exact original values before reporting success.
    func runReversibleWriteValidation() async {
        guard let repository, let original = snapshot else {
            operationError = "integration.device.not-ready"
            return
        }
        guard isPerformingAction == false else { return }

        isPerformingAction = true
        operationMessageKey = nil
        operationError = nil
        defer { isPerformingAction = false }

        var validationFailure: (any Error)?
        do {
            let temporaryScene = DeviceGlobalState(
                sceneMode: original.global.sceneMode == .flowLeft ? .flowRight : .flowLeft,
                sceneParameter: adjustedByte(original.global.sceneParameter, offset: 17)
            )
            try await repository.applyScene(temporaryScene)
            var readBack = try await repository.refreshSnapshot()
            try require(
                readBack.global.sceneMode == temporaryScene.sceneMode
                    && readBack.global.sceneParameter == temporaryScene.sceneParameter,
                step: "scene"
            )

            let temporaryGlobal = DeviceGlobalState(
                brightness: adjustedByte(original.global.brightness, offset: 23),
                redGain: adjustedByte(original.global.redGain, offset: 19),
                greenGain: adjustedByte(original.global.greenGain, offset: 29),
                blueGain: adjustedByte(original.global.blueGain, offset: 31)
            )
            try await repository.applyGlobalLED(temporaryGlobal)
            readBack = try await repository.refreshSnapshot()
            try require(
                readBack.global.brightness == temporaryGlobal.brightness
                    && readBack.global.redGain == temporaryGlobal.redGain
                    && readBack.global.greenGain == temporaryGlobal.greenGain
                    && readBack.global.blueGain == temporaryGlobal.blueGain,
                step: "global"
            )

            let originalFirst = original.groups[0]
            let temporaryFirst = DeviceGroupState(
                mode: originalFirst.mode == .strobe ? .breathing : .strobe,
                hue: UInt16((Int(originalFirst.hue) + 41) % 360),
                saturation: adjustedByte(originalFirst.saturation, offset: 37),
                value: adjustedByte(originalFirst.value, offset: 43),
                parameter: adjustedByte(originalFirst.parameter, offset: 47)
            )
            try await repository.applyGroup(index: 0, state: temporaryFirst)
            readBack = try await repository.refreshSnapshot()
            try require(readBack.groups[0] == temporaryFirst, step: "single-group")

            var temporaryAll: [DeviceGroupState] = []
            temporaryAll.reserveCapacity(DeviceRegisterMap.groupCount)
            for index in 0..<DeviceRegisterMap.groupCount {
                let group = DeviceGroupState(
                    mode: index.isMultiple(of: 2) ? .gradient : .breathing,
                    hue: UInt16((67 + index * 31) % 360),
                    saturation: UInt16(180 + index),
                    value: UInt16(150 + index),
                    parameter: UInt16(90 + index)
                )
                temporaryAll.append(group)
            }
            try await repository.applyAllGroups(temporaryAll)
            readBack = try await repository.refreshSnapshot()
            try require(readBack.groups == temporaryAll, step: "all-groups")
        } catch {
            validationFailure = error
        }

        do {
            try await repository.applyScene(original.global)
            try await repository.applyGlobalLED(original.global)
            try await repository.applyAllGroups(original.groups)
            let restored = try await repository.refreshSnapshot()
            try require(
                lightingGlobalMatches(restored.global, original.global),
                step: "restore-global"
            )
            try require(restored.groups == original.groups, step: "restore-groups")
            snapshot = restored
        } catch {
            operationError = String(describing: ReversibleWriteValidationError.restoreFailed(String(describing: error)))
            return
        }

        if let validationFailure {
            operationError = String(describing: validationFailure)
        } else {
            operationMessageKey = "device.status.write.validation.passed"
        }
    }

    func playbackContext() -> DevicePlaybackContext? {
        guard let transport, case .ready = transport.state,
            let snapshot, deviceInfo != nil
        else { return nil }
        let effectTransport = AppEffectPlaybackTransport(transport: transport) { [weak self] in
            guard let self, case .ready = self.connectionState, let info = self.deviceInfo else {
                throw PlaybackTransportError.disconnected
            }
            return PlaybackDeviceContext(
                capabilities: info.capabilities.rawValue,
                geometry: .legacyFirmwareFallback
            )
        }
        return DevicePlaybackContext(
            transport: effectTransport,
            initialGroups: snapshot.groups.map {
                MauryaEffects.EffectGroupState(
                    innerMode: Int($0.mode.rawValue), innerParameter: Int($0.parameter),
                    hue: Int($0.hue), saturation: Int($0.saturation), value: Int($0.value)
                )
            },
            unitID: snapshot.global.deviceAddress
        )
    }

    func OTAContext() -> DeviceOTAContext? {
        guard let transport, case let .ready(deviceID, _) = transport.state,
            let snapshot
        else { return nil }
        return DeviceOTAContext(
            deviceID: deviceID.uuidString,
            unitID: snapshot.global.deviceAddress,
            transport: AppOTADeviceTransport(transport: transport)
        )
    }

    func disconnect() {
        transport?.disconnect()
    }

    private func prepareTransport() throws -> any BluetoothTransporting {
        if let transport { return transport }
        let created = try transportFactory()
        transport = created
        repository = repositoryFactory(BluetoothDeviceTransportAdapter(transport: created))
        observe(created)
        return created
    }

    private func observe(_ transport: any BluetoothTransporting) {
        stateTask?.cancel()
        devicesTask?.cancel()

        stateTask = Task(name: "Maurya app BLE state observer") { [weak self] in
            for await state in transport.states {
                guard let self else { return }
                await self.consume(state)
            }
        }
        devicesTask = Task(name: "Maurya app BLE discovery observer") { [weak self] in
            for await discovered in transport.discoveredDevices {
                guard let self else { return }
                self.devices = discovered.map {
                    ScanDevice(id: $0.id, name: $0.name, rssi: $0.rssi)
                }
            }
        }
    }

    private func consume(_ state: BluetoothLifecycleState) async {
        connectionState = state
        switch state {
        case .idle:
            scanState = .idle
            if scanAfterDisconnect {
                scanAfterDisconnect = false
                startScanning()
            }
        case .waitingForBluetooth(let availability):
            scanState = .waitingForBluetooth(availability)
            await repository?.markDisconnected()
        case .scanning:
            scanState = .scanning
        case .connecting, .discoveringServices, .discoveringCharacteristics, .subscribing,
            .reconnectBackoff, .disconnecting:
            scanState = .connecting
        case .ready(let deviceID, _):
            scanState = .ready(deviceID: deviceID)
            await repository?.markConnected(unitID: nil)
            await refresh()
        case .failed(let failure):
            scanState = .failed(message: failure.detail)
            await repository?.markDisconnected()
        }
    }

    private func performAction(
        successKey: String,
        _ operation: (any DeviceRepositoryServing) async throws -> Void,
        verify: (DeviceSnapshot) -> Bool = { _ in true }
    ) async {
        guard let repository else {
            operationError = "integration.device.not-ready"
            return
        }
        guard isPerformingAction == false else { return }
        isPerformingAction = true
        operationMessageKey = nil
        defer { isPerformingAction = false }
        do {
            try await operation(repository)
            let refreshed = try await repository.refreshSnapshot()
            guard verify(refreshed) else { throw DeviceReadbackError.mismatch }
            snapshot = refreshed
            operationError = nil
            operationMessageKey = successKey
        } catch is CancellationError {
            return
        } catch {
            operationError = String(describing: error)
            operationMessageKey = nil
        }
    }

    private func adjustedByte(_ value: UInt16, offset: Int) -> UInt16 {
        UInt16((Int(min(value, 255)) + offset) % 256)
    }

    private func require(_ condition: Bool, step: String) throws {
        guard condition else { throw ReversibleWriteValidationError.readBackMismatch(step) }
    }

    private func lightingGlobalMatches(_ lhs: DeviceGlobalState, _ rhs: DeviceGlobalState) -> Bool {
        lhs.sceneMode == rhs.sceneMode
            && lhs.sceneParameter == rhs.sceneParameter
            && lhs.brightness == rhs.brightness
            && lhs.redGain == rhs.redGain
            && lhs.greenGain == rhs.greenGain
            && lhs.blueGain == rhs.blueGain
            && lhs.deviceAddress == rhs.deviceAddress
    }
}

private enum DeviceReadbackError: Error, CustomStringConvertible {
    case mismatch

    var description: String {
        "device.error.readback.mismatch"
    }
}

private enum ReversibleWriteValidationError: Error, CustomStringConvertible {
    case readBackMismatch(String)
    case restoreFailed(String)

    var description: String {
        switch self {
        case .readBackMismatch(let step): "Physical write validation failed at \(step); original values were restored."
        case .restoreFailed(let detail): "Physical write validation could not restore the original values: \(detail)"
        }
    }
}
