import Foundation
import MauryaBluetooth

struct ScanDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum ScanPresentationState: Equatable, Sendable {
    case idle
    case waitingForBluetooth(BluetoothAvailability)
    case scanning
    case connecting
    case ready(deviceID: UUID)
    case failed(message: String)
}

@MainActor
protocol DeviceDiscoveryService: AnyObject {
    var scanState: ScanPresentationState { get }
    var devices: [ScanDevice] { get }

    func startScanning()
    func stopScanning()
    func connect(to id: UUID)
    /// Leaves any active connection before presenting the device list, then
    /// resumes foreground discovery after CoreBluetooth reports idle.
    func returnToDeviceList()
}
