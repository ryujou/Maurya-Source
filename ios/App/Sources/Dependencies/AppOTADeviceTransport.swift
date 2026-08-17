import Foundation
import MauryaBluetooth
import MauryaDevice
import MauryaOTA
import MauryaProtocol

struct DeviceOTAContext: Sendable {
    let deviceID: String
    let unitID: UInt8
    let transport: any OTADeviceTransport
}

@MainActor
final class AppOTADeviceTransport: OTADeviceTransport {
    private let transport: any BluetoothTransporting

    init(transport: any BluetoothTransporting) {
        self.transport = transport
    }

    func transact(_ request: Data, timeout: Duration) async throws -> Data {
        guard case .ready = transport.state else { throw OTAFailure.disconnected }
        do {
            return try await transport.transact(request, timeout: timeout)
        } catch {
            if case .ready = transport.state { throw error }
            throw OTAFailure.disconnected
        }
    }

    func maximumFirmwareChunkByteCount() async throws -> Int {
        // MauryaCentralTransport fragments complete Modbus frames to the negotiated
        // CoreBluetooth write-with-response size, so the OTA protocol limit is authoritative here.
        OTAProtocolCodec.maximumFirmwareDataByteCount
    }

    func reconnectAndWait(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if case .ready = transport.state { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OTAFailure.reconnectFailed
    }
}
