import MauryaBluetooth
import MauryaDevice

@MainActor
final class UnavailableDeviceControlService: DeviceControlService {
    let connectionState = BluetoothLifecycleState.failed(
        BluetoothFailure(.notReady, detail: "integration.device.pending")
    )
    let snapshot: DeviceSnapshot? = nil
    let deviceInfo: DeviceInfo? = nil
    let operationError: String? = "integration.device.pending"
    let operationMessageKey: String? = nil
    let isPerformingAction = false
    let isRefreshing = false

    func refresh() async {}
    func runTelemetryPolling() async {}
    func applyScene(_ state: DeviceGlobalState) async {}
    func applyGlobalLED(_ state: DeviceGlobalState) async {}
    func applyGroup(index: Int, state: DeviceGroupState) async {}
    func applyAllGroups(_ state: DeviceGroupState) async {}
    func applyColorToAllGroups(hue: UInt16, saturation: UInt16, value: UInt16) async {}
    func clearDiagnostics() async {}
    func runReversibleWriteValidation() async {}
    func playbackContext() -> DevicePlaybackContext? { nil }
    func reconnect() {}
    func disconnect() {}
}
