import MauryaDevice

protocol DeviceRepositoryServing: Sendable {
    func markConnected(unitID: UInt8?) async
    func markDisconnected() async
    func refreshSnapshot() async throws -> DeviceSnapshot
    func refreshTelemetry() async throws -> DeviceDiagnostics
    func fetchDeviceInfo() async throws -> DeviceInfo
    func applyScene(_ state: DeviceGlobalState) async throws
    func applyGlobalLED(_ state: DeviceGlobalState) async throws
    func applyGroup(index: Int, state: DeviceGroupState) async throws
    func applyAllGroups(_ groups: [DeviceGroupState]) async throws
    func clearDiagnostics() async throws
}

extension DeviceRepository: DeviceRepositoryServing {}
