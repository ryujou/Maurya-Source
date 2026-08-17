import Foundation

public struct OTAManifest: Codable, Equatable, Sendable {
    public let schema: Int
    public let variant: String
    public let layoutVersion: UInt8
    public let assetPackVersion: UInt8
    public let versionName: String
    public let monotonicVersion: UInt32
    public let secureVersion: UInt32
    public let size: UInt64
    public let sha256: String
    public let downloadURL: URL
    public let minimumAppVersion: Int
    public let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case schema, variant, layoutVersion, assetPackVersion, versionName
        case monotonicVersion, secureVersion, size, sha256
        case downloadURL = "downloadUrl"
        case minimumAppVersion, publishedAt
    }

    public init(
        schema: Int,
        variant: String,
        layoutVersion: UInt8,
        assetPackVersion: UInt8,
        versionName: String,
        monotonicVersion: UInt32,
        secureVersion: UInt32,
        size: UInt64,
        sha256: String,
        downloadURL: URL,
        minimumAppVersion: Int,
        publishedAt: String? = nil
    ) {
        self.schema = schema
        self.variant = variant
        self.layoutVersion = layoutVersion
        self.assetPackVersion = assetPackVersion
        self.versionName = versionName
        self.monotonicVersion = monotonicVersion
        self.secureVersion = secureVersion
        self.size = size
        self.sha256 = sha256
        self.downloadURL = downloadURL
        self.minimumAppVersion = minimumAppVersion
        self.publishedAt = publishedAt
    }
}

public struct SignedOTAManifest: Equatable, Sendable {
    public let manifestBytes: Data
    public let detachedSignature: Data
    public let keyID: String

    public init(manifestBytes: Data, detachedSignature: Data, keyID: String) {
        self.manifestBytes = manifestBytes
        self.detachedSignature = detachedSignature
        self.keyID = keyID
    }
}

public struct OTAArtifact: Equatable, Sendable {
    public let bytes: Data
    public let sourceURL: URL
    public let entityTag: String?

    public init(bytes: Data, sourceURL: URL, entityTag: String? = nil) {
        self.bytes = bytes
        self.sourceURL = sourceURL
        self.entityTag = entityTag
    }
}

public struct OTADeviceInformation: Equatable, Sendable {
    public let protocolVersion: UInt8
    public let layoutVersion: UInt8
    public let firmwareVersion: String
    public let variant: String
    public let assetPackVersion: UInt8
    public let capabilities: UInt8
    public let secureVersion: UInt32

    public init(
        protocolVersion: UInt8,
        layoutVersion: UInt8,
        firmwareVersion: String,
        variant: String,
        assetPackVersion: UInt8,
        capabilities: UInt8,
        secureVersion: UInt32
    ) {
        self.protocolVersion = protocolVersion
        self.layoutVersion = layoutVersion
        self.firmwareVersion = firmwareVersion
        self.variant = variant
        self.assetPackVersion = assetPackVersion
        self.capabilities = capabilities
        self.secureVersion = secureVersion
    }
}

public struct OTABLEStatus: Equatable, Sendable {
    public enum State: UInt8, Sendable {
        case waiting = 0
        case receiving = 1
        case verifying = 2
        case verified = 3
        case rebooting = 4
        case failed = 5
    }

    public let state: State
    public let receivedBytes: UInt32
    public let expectedBytes: UInt32
    public let errorCode: UInt32
}

public struct OTAWiFiSession: Equatable, Sendable {
    public let ssid: String
    public let bssid: Data
    public let token: Data
    public let timeoutSeconds: UInt32
}

public enum OTACommitCheckpointState: String, Codable, Equatable, Sendable {
    /// The device reported VERIFIED, but COMMIT has not been attempted.
    case verified
    /// COMMIT may have reached the device, but no valid response was received.
    case requestOutcomeUnknown
    /// A valid COMMIT response was received.
    case confirmed
}

public struct OTACheckpoint: Codable, Equatable, Sendable {
    public let deviceID: String
    public let versionName: String
    public let secureVersion: UInt32
    public let size: UInt64
    public let sha256: String
    public let entityTag: String?
    public var confirmedOffset: UInt32
    public var didCommit: Bool
    /// Optional so checkpoints written by earlier app versions remain decodable.
    public var commitState: OTACommitCheckpointState?

    public init(
        deviceID: String,
        manifest: OTAManifest,
        entityTag: String?,
        confirmedOffset: UInt32 = 0,
        didCommit: Bool = false,
        commitState: OTACommitCheckpointState? = nil
    ) {
        self.deviceID = deviceID
        self.versionName = manifest.versionName
        self.secureVersion = manifest.secureVersion
        self.size = manifest.size
        self.sha256 = manifest.sha256.lowercased()
        self.entityTag = entityTag
        self.confirmedOffset = confirmedOffset
        self.didCommit = didCommit
        self.commitState = commitState
    }

    func matches(deviceID: String, manifest: OTAManifest, entityTag: String?) -> Bool {
        self.deviceID == deviceID && versionName == manifest.versionName && secureVersion == manifest.secureVersion && size == manifest.size
            && sha256 == manifest.sha256.lowercased() && self.entityTag == entityTag
    }

    func matchesTarget(deviceID: String, manifest: OTAManifest) -> Bool {
        self.deviceID == deviceID && versionName == manifest.versionName && secureVersion == manifest.secureVersion
            && size == manifest.size && sha256 == manifest.sha256.lowercased()
    }

    var resolvedCommitState: OTACommitCheckpointState? {
        commitState ?? (didCommit ? .requestOutcomeUnknown : nil)
    }
}

public enum OTAWorkflowStage: String, Equatable, Sendable {
    case idle, gettingInfo, fetchingManifest, validatingManifest, downloading
    case validatingArtifact, preparing, transferring, verifying, committing
    case reconnecting, confirmingVersion, cancelled, failed, succeeded, upToDate
}

public struct OTAWorkflowSnapshot: Equatable, Sendable {
    public let stage: OTAWorkflowStage
    public let confirmedBytes: UInt64
    public let totalBytes: UInt64
    public let installedVersion: String?
    public let targetVersion: String?

    public init(
        stage: OTAWorkflowStage,
        confirmedBytes: UInt64,
        totalBytes: UInt64,
        installedVersion: String?,
        targetVersion: String?
    ) {
        self.stage = stage
        self.confirmedBytes = confirmedBytes
        self.totalBytes = totalBytes
        self.installedVersion = installedVersion
        self.targetVersion = targetVersion
    }

    public var progress: Double {
        totalBytes == 0 ? 0 : min(1, Double(confirmedBytes) / Double(totalBytes))
    }
}

public struct OTAWorkflowPolicy: Equatable, Sendable {
    public var commandTimeout: Duration
    public var reconnectTimeout: Duration
    public var maximumChunkAttempts: Int
    public var maximumVerificationPolls: Int
    public var verificationPollDelay: Duration
    public var maximumReconnectAttempts: Int
    public var maximumArtifactBytes: UInt64

    public init(
        commandTimeout: Duration = .seconds(3),
        reconnectTimeout: Duration = .seconds(15),
        maximumChunkAttempts: Int = 3,
        maximumVerificationPolls: Int = 150,
        verificationPollDelay: Duration = .milliseconds(300),
        maximumReconnectAttempts: Int = 2,
        maximumArtifactBytes: UInt64 = 2 * 1024 * 1024
    ) {
        precondition(maximumChunkAttempts > 0)
        precondition(maximumVerificationPolls > 0)
        precondition(maximumReconnectAttempts >= 0)
        precondition(maximumArtifactBytes > 0)
        self.commandTimeout = commandTimeout
        self.reconnectTimeout = reconnectTimeout
        self.maximumChunkAttempts = maximumChunkAttempts
        self.maximumVerificationPolls = maximumVerificationPolls
        self.verificationPollDelay = verificationPollDelay
        self.maximumReconnectAttempts = maximumReconnectAttempts
        self.maximumArtifactBytes = maximumArtifactBytes
    }
}

public enum OTAFailure: Error, Equatable, Sendable {
    case invalidManifest(String)
    case invalidSignature
    case unknownSigningKey(String)
    case insecureURL
    case untrustedHost(String)
    case artifactTooLarge(UInt64)
    case artifactSizeMismatch(expected: UInt64, actual: UInt64)
    case artifactHashMismatch
    case appUpgradeRequired(minimumVersion: Int)
    case unsupportedBLEOTA
    case incompatibleProtocol(actual: UInt8)
    case incompatibleLayout(device: UInt8, manifest: UInt8)
    case incompatibleAssetPack(device: UInt8, manifest: UInt8)
    case incompatibleVariant(device: String, manifest: String)
    case secureVersionRollback(device: UInt32, manifest: UInt32)
    case invalidWriteCapacity(Int)
    case invalidAcknowledgedOffset(expected: UInt32, actual: UInt32)
    case deviceVerificationFailed(UInt32)
    case verificationTimedOut
    case disconnected
    case responseTimedOut
    case reconnectFailed
    case committedDeviceDidNotReturn
    case installedVersionUnchanged(expected: String, actual: String)
    case cancelled
    case busy
    case protocolViolation(String)
    case network(String)
    case storage(String)
}
