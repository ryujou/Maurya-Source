import Foundation

@MainActor
final class UnavailableDeviceDiscoveryService: DeviceDiscoveryService {
    let scanState = ScanPresentationState.failed(message: "integration.ble.pending")
    let devices: [ScanDevice] = []

    func startScanning() {}
    func stopScanning() {}
    func connect(to id: UUID) {}
    func returnToDeviceList() {}
}
