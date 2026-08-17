import Foundation
import MauryaBluetooth
import MauryaDevice
import MauryaEffects
import MauryaPlayback

struct DevicePlaybackContext: Sendable {
    let transport: any EffectPlaybackTransport
    let initialGroups: [MauryaEffects.EffectGroupState]
    let unitID: UInt8
}

@MainActor
protocol DeviceControlService: AnyObject {
    var connectionState: BluetoothLifecycleState { get }
    var snapshot: DeviceSnapshot? { get }
    var deviceInfo: DeviceInfo? { get }
    var operationError: String? { get }
    var operationMessageKey: String? { get }
    var isPerformingAction: Bool { get }
    var isRefreshing: Bool { get }

    func refresh() async
    func runTelemetryPolling() async
    func applyScene(_ state: DeviceGlobalState) async
    func applyGlobalLED(_ state: DeviceGlobalState) async
    func applyGroup(index: Int, state: DeviceGroupState) async
    func applyAllGroups(_ state: DeviceGroupState) async
    func applyColorToAllGroups(hue: UInt16, saturation: UInt16, value: UInt16) async
    func clearDiagnostics() async
    func runReversibleWriteValidation() async
    func playbackContext() -> DevicePlaybackContext?
    func reconnect()
    func disconnect()
}
