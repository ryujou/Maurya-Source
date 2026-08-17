import Foundation
import MauryaBluetooth
import MauryaDevice
import MauryaProtocol

@testable import MauryaOTA

actor FakeOTADeviceTransport: OTADeviceTransport {
    enum Mode: Sendable {
        case normal
        case loseAcknowledgementOnce(offset: UInt32)
        case badAcknowledgement
        case verificationFailure(code: UInt32)
        case neverVerifies
        case unchangedAfterCommit
        case commitFailsBeforeSendOnce
        case commitResponseLostAndReconnectFailsOnce
    }

    let initialVersion: String
    let targetVersion: String
    let chunkCapacity: Int
    let mode: Mode
    var deviceOffset: UInt32
    var expectedBytes: UInt32
    var began = 0
    var committed = 0
    var cancelled = 0
    var reconnects = 0
    var chunkOffsets: [UInt32] = []
    var lostAcknowledgement = false
    var commitFailureInjected = false
    var commitResponseLossInjected = false
    var reconnectFailureInjected = false

    init(
        initialVersion: String = "1.8.0",
        targetVersion: String = "1.9.0",
        chunkCapacity: Int = 50,
        mode: Mode = .normal,
        deviceOffset: UInt32 = 0,
        expectedBytes: UInt32 = 0
    ) {
        self.initialVersion = initialVersion
        self.targetVersion = targetVersion
        self.chunkCapacity = chunkCapacity
        self.mode = mode
        self.deviceOffset = deviceOffset
        self.expectedBytes = expectedBytes
    }

    func maximumFirmwareChunkByteCount() -> Int { chunkCapacity }

    func reconnectAndWait(timeout: Duration) async throws {
        reconnects += 1
        if case .commitResponseLostAndReconnectFailsOnce = mode,
            commitResponseLossInjected,
            reconnectFailureInjected == false
        {
            reconnectFailureInjected = true
            throw BluetoothFailure(.disconnected, detail: "injected reconnect failure")
        }
    }

    func transact(_ request: Data, timeout: Duration) async throws -> Data {
        let command = request[request.startIndex + 3]
        switch command {
        case OTACommand.getInfo.rawValue:
            let installed = committed > 0 && !isUnchanged
            return try infoResponse(
                version: installed ? targetVersion : initialVersion,
                secureVersion: installed ? 190 : 180
            )
        case OTACommand.bleBegin.rawValue:
            began += 1
            expectedBytes = readUInt32(request, at: 4)
            deviceOffset = 0
            return try response(command: command)
        case OTACommand.bleData.rawValue:
            let offset = readUInt32(request, at: 4)
            let length = UInt32(Int(request[request.startIndex + 2]) - 5)
            guard offset == deviceOffset else { throw BluetoothFailure(.writeFailed, detail: "offset") }
            chunkOffsets.append(offset)
            deviceOffset += length
            if case .loseAcknowledgementOnce(let failingOffset) = mode,
                offset == failingOffset, lostAcknowledgement == false
            {
                lostAcknowledgement = true
                throw BluetoothFailure(.disconnected)
            }
            let acknowledged: UInt32 = modeIsBadAcknowledgement ? deviceOffset + 1 : deviceOffset
            return try response(command: command, tlvs: [(0x20, littleEndian(acknowledged))])
        case OTACommand.bleStatus.rawValue:
            let state: UInt8
            let error: UInt32
            switch mode {
            case .verificationFailure(let code) where deviceOffset == expectedBytes:
                state = OTABLEStatus.State.failed.rawValue
                error = code
            case .neverVerifies where deviceOffset == expectedBytes:
                state = OTABLEStatus.State.verifying.rawValue
                error = 0
            default:
                state =
                    deviceOffset == expectedBytes && expectedBytes > 0
                    ? OTABLEStatus.State.verified.rawValue
                    : OTABLEStatus.State.receiving.rawValue
                error = 0
            }
            return try response(
                command: command,
                tlvs: [
                    (0x21, Data([state])),
                    (0x22, littleEndian(deviceOffset)),
                    (0x23, littleEndian(expectedBytes)),
                    (0x24, littleEndian(error)),
                ])
        case OTACommand.bleCommit.rawValue:
            if case .commitFailsBeforeSendOnce = mode, commitFailureInjected == false {
                commitFailureInjected = true
                throw OTAFailure.protocolViolation("injected pre-send failure")
            }
            if case .commitResponseLostAndReconnectFailsOnce = mode,
                commitResponseLossInjected == false
            {
                commitResponseLossInjected = true
                committed += 1
                throw BluetoothFailure(.disconnected, detail: "injected response loss")
            }
            committed += 1
            return try response(command: command)
        case OTACommand.bleCancel.rawValue:
            cancelled += 1
            return try response(command: command)
        default:
            throw BluetoothFailure(.protocolDecodeFailed, detail: "unexpected command")
        }
    }

    func metrics() -> (began: Int, committed: Int, cancelled: Int, reconnects: Int, offsets: [UInt32]) {
        (began, committed, cancelled, reconnects, chunkOffsets)
    }

    private var isUnchanged: Bool {
        if case .unchangedAfterCommit = mode { true } else { false }
    }

    private var modeIsBadAcknowledgement: Bool {
        if case .badAcknowledgement = mode { true } else { false }
    }

    private func infoResponse(version: String, secureVersion: UInt32) throws -> Data {
        try response(
            command: OTACommand.getInfo.rawValue,
            tlvs: [
                (0x01, Data([2])),
                (0x02, Data([2])),
                (0x03, Data("multilingual".utf8)),
                (0x04, Data([1])),
                (0x05, Data([OTAProtocolCodec.bleOTACapability])),
                (0x06, littleEndian(secureVersion)),
                (0x07, Data(version.utf8)),
            ])
    }

    private func response(command: UInt8, tlvs: [(UInt8, Data)] = []) throws -> Data {
        let body = try VendorTLVCodec.encode(tlvs.map { VendorTLV(type: $0.0, value: $0.1) })
        return try ModbusRequest.vendor(unitID: 1, payload: Data([command, 0]) + body)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = data.dropFirst(offset).prefix(4)
        return bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
    }

    private func littleEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ])
    }
}

actor FakeOTANetwork: OTAHTTPSClient {
    let signedManifest: SignedOTAManifest
    let artifact: OTAArtifact
    var artifactFetches = 0

    init(manifest: OTAManifest, artifactBytes: Data, artifactOverride: Data? = nil) throws {
        let bytes = try JSONEncoder().encode(manifest)
        self.signedManifest = SignedOTAManifest(
            manifestBytes: bytes,
            detachedSignature: Data("signature".utf8),
            keyID: "test"
        )
        self.artifact = OTAArtifact(
            bytes: artifactOverride ?? artifactBytes,
            sourceURL: manifest.downloadURL,
            entityTag: "fixture-etag"
        )
    }

    func fetchSignedManifest(channel: String, variant: String) -> SignedOTAManifest {
        signedManifest
    }

    func fetchArtifact(from url: URL, maximumBytes: UInt64) throws -> OTAArtifact {
        artifactFetches += 1
        guard UInt64(artifact.bytes.count) <= maximumBytes else {
            throw OTAFailure.artifactTooLarge(UInt64(artifact.bytes.count))
        }
        return artifact
    }

    func artifactFetchCount() -> Int { artifactFetches }
}

struct FakeSignatureVerifier: OTASignatureVerifying {
    let failure: OTAFailure?

    init(failure: OTAFailure? = nil) { self.failure = failure }

    func verify(message: Data, detachedSignature: Data, keyID: String) throws {
        if let failure { throw failure }
    }
}

actor MemoryCheckpointStore: OTACheckpointStore {
    var values: [String: OTACheckpoint] = [:]
    var saves = 0

    func load(deviceID: String) -> OTACheckpoint? { values[deviceID] }
    func save(_ checkpoint: OTACheckpoint) {
        saves += 1
        values[checkpoint.deviceID] = checkpoint
    }
    func remove(deviceID: String) { values[deviceID] = nil }
    func value(_ deviceID: String) -> OTACheckpoint? { values[deviceID] }
    func saveCount() -> Int { saves }
}

func fixture(artifact: Data = Data((0..<125).map(UInt8.init))) -> (OTAManifest, Data) {
    let manifest = OTAManifest(
        schema: 1,
        variant: "multilingual",
        layoutVersion: 2,
        assetPackVersion: 1,
        versionName: "1.9.0",
        monotonicVersion: 190,
        secureVersion: 190,
        size: UInt64(artifact.count),
        sha256: OTADigest.sha256Hex(artifact),
        downloadURL: URL(string: "https://xtbang.top/maurya/ota/stable/multilingual/maurya-1.9.0.bin")!,
        minimumAppVersion: 313,
        publishedAt: "2026-08-08T00:00:00Z"
    )
    return (manifest, artifact)
}

func workflow(
    transport: FakeOTADeviceTransport,
    network: FakeOTANetwork,
    store: MemoryCheckpointStore,
    verifier: FakeSignatureVerifier = .init(),
    policy: OTAWorkflowPolicy = .init()
) -> OTAWorkflow {
    OTAWorkflow(
        transport: transport,
        network: network,
        signatureVerifier: verifier,
        checkpointStore: store,
        appVersion: 421,
        allowedArtifactHosts: ["xtbang.top"],
        sleeper: .init { _ in try Task.checkCancellation() },
        policy: policy
    )
}
