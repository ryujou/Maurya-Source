import Foundation
import MauryaBluetooth
import MauryaDevice
import Testing

@testable import Maurya

@MainActor
struct LiveDeviceServiceTests {
    @Test func scanUsesInjectedForegroundTransport() throws {
        let transport = FakeBluetoothTransport()
        let service = LiveDeviceService(transportFactory: { transport })

        service.startScanning()

        #expect(transport.requestedScanScope == .foreground)
    }

    @Test func connectUsesSelectedPeripheralIdentifier() throws {
        let id = UUID()
        let transport = FakeBluetoothTransport()
        let service = LiveDeviceService(transportFactory: { transport })

        service.connect(to: id)

        #expect(transport.connectedID == id)
    }

    @Test func reconnectUsesLastSelectedPeripheralIdentifier() {
        let id = UUID()
        let transport = FakeBluetoothTransport()
        let service = LiveDeviceService(transportFactory: { transport })

        service.connect(to: id)
        transport.connectedID = nil
        service.reconnect()

        #expect(transport.connectedID == id)
    }

    @Test func returningToDeviceListDisconnectsBeforeScanningAgain() async {
        let transport = FakeBluetoothTransport()
        let service = LiveDeviceService(transportFactory: { transport })
        service.startScanning()
        transport.emitReady()
        while service.scanState != .ready(deviceID: transport.readyDeviceID) { await Task.yield() }

        service.returnToDeviceList()

        while transport.requestedScanScope != .foreground || transport.disconnectCount != 1 {
            await Task.yield()
        }
        #expect(transport.disconnectCount == 1)
        #expect(transport.requestedScanScope == .foreground)
    }

    @Test func sceneAndGlobalCommandsUseRepositoryAndRefreshSnapshot() async throws {
        let transport = FakeBluetoothTransport()
        let repository = FakeDeviceRepository()
        let service = LiveDeviceService(
            transportFactory: { transport },
            repositoryFactory: { _ in repository }
        )
        service.startScanning()
        let scene = DeviceGlobalState(sceneMode: .flowLeft, sceneParameter: 44)
        let global = DeviceGlobalState(brightness: 90, redGain: 80, greenGain: 70, blueGain: 60)

        await service.applyScene(scene)
        await service.applyGlobalLED(global)

        #expect(await repository.appliedScene == scene)
        #expect(await repository.appliedGlobalLED == global)
        #expect(service.snapshot != nil)
        #expect(service.operationError == nil)
        #expect(service.operationMessageKey == "device.status.global.applied")
        #expect(service.isPerformingAction == false)
    }

    @Test func diagnosticClearUsesRepositoryAndRefreshes() async {
        let transport = FakeBluetoothTransport()
        let repository = FakeDeviceRepository()
        let service = LiveDeviceService(
            transportFactory: { transport },
            repositoryFactory: { _ in repository }
        )
        service.startScanning()

        await service.clearDiagnostics()

        #expect(await repository.didClearDiagnostics)
        #expect(service.operationError == nil)
    }

    @Test func allGroupsCommandUsesExactlySevenIdenticalStates() async {
        let transport = FakeBluetoothTransport()
        let repository = FakeDeviceRepository()
        let service = LiveDeviceService(
            transportFactory: { transport },
            repositoryFactory: { _ in repository }
        )
        service.startScanning()
        let state = DeviceGroupState(mode: .strobe, hue: 42, saturation: 200, value: 180, parameter: 91)

        await service.applyAllGroups(state)

        let applied = await repository.appliedAllGroups
        #expect(applied?.count == DeviceRegisterMap.groupCount)
        #expect(applied?.allSatisfy { $0 == state } == true)
        #expect(service.operationMessageKey == "device.status.groups.applied")
    }

    @Test func supportColorChangesAllGroupsWithoutReplacingModesOrParameters() async {
        let groups = (0..<DeviceRegisterMap.groupCount).map { index in
            DeviceGroupState(
                mode: index.isMultiple(of: 2) ? .steady : .strobe,
                hue: UInt16(index), saturation: 10, value: 20,
                parameter: UInt16(30 + index)
            )
        }
        let transport = FakeBluetoothTransport()
        let repository = FakeDeviceRepository(groups: groups)
        let service = LiveDeviceService(
            transportFactory: { transport },
            repositoryFactory: { _ in repository }
        )
        service.startScanning()
        await service.refresh()

        await service.applyColorToAllGroups(hue: 240, saturation: 200, value: 180)

        let applied = await repository.appliedAllGroups
        #expect(applied?.count == DeviceRegisterMap.groupCount)
        #expect(applied?.map(\.mode) == groups.map(\.mode))
        #expect(applied?.map(\.parameter) == groups.map(\.parameter))
        #expect(applied?.allSatisfy { $0.hue == 240 && $0.saturation == 200 && $0.value == 180 } == true)
        #expect(service.operationMessageKey == "device.status.color.applied")
    }

    @Test func singleGroupCommandIsReadBackBeforeReportingSuccess() async {
        let repository = FakeDeviceRepository()
        let service = LiveDeviceService(
            transportFactory: { FakeBluetoothTransport() },
            repositoryFactory: { _ in repository }
        )
        service.startScanning()
        let state = DeviceGroupState(mode: .gradient, hue: 275, saturation: 211, value: 199, parameter: 73)

        await service.applyGroup(index: 4, state: state)

        #expect(await repository.appliedGroupIndex == 4)
        #expect(service.snapshot?.groups[4] == state)
        #expect(service.operationError == nil)
        #expect(service.operationMessageKey == "device.status.group.applied")
    }

    @Test func acknowledgedWriteWithMismatchedReadBackIsNotReportedAsSuccess() async {
        let repository = FakeDeviceRepository(ignoresWrites: true)
        let service = LiveDeviceService(
            transportFactory: { FakeBluetoothTransport() },
            repositoryFactory: { _ in repository }
        )
        service.startScanning()

        await service.applyScene(DeviceGlobalState(sceneMode: .flowRight, sceneParameter: 37))

        #expect(service.operationMessageKey == nil)
        #expect(service.operationError == "device.error.readback.mismatch")
        #expect(service.isPerformingAction == false)
    }

    @Test func telemetryPollingRefreshesDiagnosticsAndStopsOnCancellation() async {
        let transport = FakeBluetoothTransport()
        let repository = FakeDeviceRepository()
        let sleeper = OneCycleSleeper()
        let service = LiveDeviceService(
            transportFactory: { transport },
            repositoryFactory: { _ in repository },
            telemetrySleeper: { duration in try await sleeper.sleep(duration) }
        )
        service.startScanning()
        transport.emitReady()
        while service.snapshot == nil { await Task.yield() }

        await service.runTelemetryPolling()

        #expect(service.snapshot?.diagnostics.receiveCount == 42)
        let sleepCalls = await sleeper.callCount
        #expect(sleepCalls == 2)
    }
}

private actor OneCycleSleeper {
    private(set) var callCount = 0

    func sleep(_: Duration) throws {
        callCount += 1
        if callCount > 1 { throw CancellationError() }
    }
}

private actor FakeDeviceRepository: DeviceRepositoryServing {
    private(set) var appliedScene: DeviceGlobalState?
    private(set) var appliedGlobalLED: DeviceGlobalState?
    private(set) var didClearDiagnostics = false
    private(set) var appliedAllGroups: [DeviceGroupState]?
    private(set) var appliedGroupIndex: Int?
    private let ignoresWrites: Bool
    private var global = DeviceGlobalState()
    private var groups: [DeviceGroupState]

    init(
        groups: [DeviceGroupState] = Array(repeating: DeviceGroupState(), count: DeviceRegisterMap.groupCount),
        ignoresWrites: Bool = false
    ) {
        self.groups = groups
        self.ignoresWrites = ignoresWrites
    }

    func markConnected(unitID: UInt8?) {}
    func markDisconnected() {}

    func refreshSnapshot() throws -> DeviceSnapshot {
        try DeviceSnapshot(
            global: global,
            groups: groups,
            diagnostics: DeviceDiagnostics()
        )
    }

    func refreshTelemetry() -> DeviceDiagnostics { DeviceDiagnostics(receiveCount: 42) }

    func fetchDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            protocolVersion: 2,
            layoutVersion: 1,
            firmwareVersion: "test",
            variant: "test",
            assetPackVersion: 1,
            capabilities: [],
            secureVersion: 1
        )
    }

    func applyScene(_ state: DeviceGlobalState) {
        appliedScene = state
        guard ignoresWrites == false else { return }
        global.sceneMode = state.sceneMode
        global.sceneParameter = min(state.sceneParameter, 255)
    }

    func applyGlobalLED(_ state: DeviceGlobalState) {
        appliedGlobalLED = state
        guard ignoresWrites == false else { return }
        global.brightness = min(state.brightness, 255)
        global.redGain = min(state.redGain, 255)
        global.greenGain = min(state.greenGain, 255)
        global.blueGain = min(state.blueGain, 255)
    }

    func applyGroup(index: Int, state: DeviceGroupState) {
        appliedGroupIndex = index
        guard ignoresWrites == false, groups.indices.contains(index) else { return }
        groups[index] = state
    }

    func applyAllGroups(_ updated: [DeviceGroupState]) {
        appliedAllGroups = updated
        guard ignoresWrites == false else { return }
        groups = updated
    }
    func clearDiagnostics() { didClearDiagnostics = true }
}

@MainActor
private final class FakeBluetoothTransport: BluetoothTransporting {
    let states: AsyncStream<BluetoothLifecycleState>
    let discoveredDevices: AsyncStream<[DiscoveredMauryaDevice]>
    private(set) var state = BluetoothLifecycleState.idle
    private(set) var requestedScanScope: BluetoothScanScope?
    var connectedID: UUID?
    let readyDeviceID = UUID()
    private(set) var disconnectCount = 0

    private let stateContinuation: AsyncStream<BluetoothLifecycleState>.Continuation
    private let devicesContinuation: AsyncStream<[DiscoveredMauryaDevice]>.Continuation

    init() {
        let statePair = AsyncStream.makeStream(of: BluetoothLifecycleState.self)
        states = statePair.stream
        stateContinuation = statePair.continuation
        let devicePair = AsyncStream.makeStream(of: [DiscoveredMauryaDevice].self)
        discoveredDevices = devicePair.stream
        devicesContinuation = devicePair.continuation
    }

    func startScanning(scope: BluetoothScanScope) throws {
        requestedScanScope = scope
        state = .scanning
        stateContinuation.yield(.scanning)
    }

    func stopScanning() {
        state = .idle
        stateContinuation.yield(.idle)
    }

    func connect(id: UUID) throws {
        connectedID = id
    }

    func disconnect() {
        disconnectCount += 1
        requestedScanScope = nil
        state = .idle
        stateContinuation.yield(.idle)
    }

    func emitReady() {
        state = .ready(deviceID: readyDeviceID, generation: .initial)
        stateContinuation.yield(state)
    }

    func transact(_ request: Data, timeout: Duration?) async throws -> Data {
        throw BluetoothFailure(.notReady)
    }

    func close() async {
        stateContinuation.finish()
        devicesContinuation.finish()
    }
}
