import Foundation
import MauryaBluetooth
import MauryaDevice

@MainActor
protocol BluetoothTransporting: AnyObject, Sendable {
    var states: AsyncStream<BluetoothLifecycleState> { get }
    var discoveredDevices: AsyncStream<[DiscoveredMauryaDevice]> { get }
    var state: BluetoothLifecycleState { get }

    func startScanning(scope: BluetoothScanScope) throws
    func stopScanning()
    func connect(id: UUID) throws
    func disconnect()
    func transact(_ request: Data, timeout: Duration?) async throws -> Data
    func close() async
}

extension MauryaCentralTransport: BluetoothTransporting {}

@MainActor
final class BluetoothDeviceTransportAdapter: DeviceTransport {
    private let transport: any BluetoothTransporting

    init(transport: any BluetoothTransporting) {
        self.transport = transport
    }

    func transact(_ request: Data, timeout: Duration) async throws -> Data {
        try await transport.transact(request, timeout: timeout)
    }
}
