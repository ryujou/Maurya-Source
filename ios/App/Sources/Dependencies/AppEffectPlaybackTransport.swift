import Foundation
import MauryaDevice
import MauryaPlayback
import MauryaProtocol

@MainActor
final class AppEffectPlaybackTransport: EffectPlaybackTransport {
    private let transport: any BluetoothTransporting
    private let context: @MainActor () throws -> PlaybackDeviceContext

    init(
        transport: any BluetoothTransporting,
        context: @escaping @MainActor () throws -> PlaybackDeviceContext
    ) {
        self.transport = transport
        self.context = context
    }

    func refreshDeviceContext() throws -> PlaybackDeviceContext {
        try context()
    }

    func exchange(_ request: Data) async throws -> Data {
        guard case .ready = transport.state else { throw PlaybackTransportError.disconnected }
        do {
            return try await transport.transact(request, timeout: .seconds(3))
        } catch {
            if case .ready = transport.state { throw error }
            throw PlaybackTransportError.disconnected
        }
    }

    func sendBestEffort(_ request: Data) async {
        guard case .ready = transport.state else { return }
        _ = try? await transport.transact(request, timeout: .seconds(1))
    }
}
