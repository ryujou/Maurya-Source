import Foundation
import MauryaDevice
import Security

public protocol OTAHTTPSClient: Sendable {
    func fetchSignedManifest(channel: String, variant: String) async throws -> SignedOTAManifest
    func fetchArtifact(from url: URL, maximumBytes: UInt64) async throws -> OTAArtifact
}

public protocol OTASignatureVerifying: Sendable {
    func verify(message: Data, detachedSignature: Data, keyID: String) throws
}

public protocol OTACheckpointStore: Sendable {
    func load(deviceID: String) async throws -> OTACheckpoint?
    func save(_ checkpoint: OTACheckpoint) async throws
    func remove(deviceID: String) async throws
}

/// The app adapter may wrap `MauryaCentralTransport`; inherited transactions
/// retain MauryaDevice's strict timeout and cancellation contract.
public protocol OTADeviceTransport: DeviceTransport {
    func maximumFirmwareChunkByteCount() async throws -> Int
    func reconnectAndWait(timeout: Duration) async throws
}

public protocol OTANonceGenerating: Sendable {
    func makeNonce() throws -> Data
}

public struct SystemOTANonceGenerator: OTANonceGenerating {
    public init() {}

    public func makeNonce() throws -> Data {
        var bytes = Data(count: 16)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw OTAFailure.protocolViolation("Secure nonce generation failed: \(result)")
        }
        return bytes
    }
}

public struct ClosureOTASleeper: Sendable {
    public let sleep: @Sendable (Duration) async throws -> Void

    public init(_ sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.sleep = sleep
    }

    public static let continuous = Self { try await Task.sleep(for: $0) }
}
