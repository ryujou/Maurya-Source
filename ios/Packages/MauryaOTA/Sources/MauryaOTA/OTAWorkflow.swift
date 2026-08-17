import Foundation
import MauryaBluetooth
import MauryaDevice
import MauryaProtocol

public actor OTAWorkflow {
    public typealias Observer = @Sendable (OTAWorkflowSnapshot) -> Void

    private let transport: any OTADeviceTransport
    private let network: any OTAHTTPSClient
    private let signatureVerifier: any OTASignatureVerifying
    private let checkpointStore: any OTACheckpointStore
    private let nonceGenerator: any OTANonceGenerating
    private let sleeper: ClosureOTASleeper
    private let policy: OTAWorkflowPolicy
    private let appVersion: Int
    private let allowedArtifactHosts: Set<String>

    private var current = OTAWorkflowSnapshot(
        stage: .idle,
        confirmedBytes: 0,
        totalBytes: 0,
        installedVersion: nil,
        targetVersion: nil
    )
    private var isRunning = false
    private var cancellationRequested = false
    private var activeDeviceID: String?
    private var activeUnitID: UInt8?
    private var activeCheckpoint: OTACheckpoint?

    public init(
        transport: any OTADeviceTransport,
        network: any OTAHTTPSClient,
        signatureVerifier: any OTASignatureVerifying,
        checkpointStore: any OTACheckpointStore,
        appVersion: Int,
        allowedArtifactHosts: Set<String>,
        nonceGenerator: any OTANonceGenerating = SystemOTANonceGenerator(),
        sleeper: ClosureOTASleeper = .continuous,
        policy: OTAWorkflowPolicy = .init()
    ) {
        self.transport = transport
        self.network = network
        self.signatureVerifier = signatureVerifier
        self.checkpointStore = checkpointStore
        self.appVersion = appVersion
        self.allowedArtifactHosts = Set(allowedArtifactHosts.map { $0.lowercased() })
        self.nonceGenerator = nonceGenerator
        self.sleeper = sleeper
        self.policy = policy
    }

    public func snapshot() -> OTAWorkflowSnapshot { current }

    /// The legacy Wi-Fi migration path. PREPARE stores a nonce and reboots the
    /// firmware into SoftAP mode, so the BLE update workflow never calls this.
    public func prepareWiFiSession(unitID: UInt8) async throws -> OTAWiFiSession {
        let nonce = try nonceGenerator.makeNonce()
        let request = try OTAProtocolCodec.prepareRequest(unitID: unitID, nonce: nonce)
        let response = try await transport.transact(request, timeout: policy.commandTimeout)
        return try OTAResponseCodec.wifiSession(response, unitID: unitID)
    }

    @discardableResult
    public func run(
        deviceID: String,
        unitID: UInt8 = 1,
        channel: String = "stable",
        observer: @escaping Observer = { _ in }
    ) async throws -> OTAWorkflowSnapshot {
        guard isRunning == false else { throw OTAFailure.busy }
        isRunning = true
        cancellationRequested = false
        activeDeviceID = deviceID
        activeUnitID = unitID
        activeCheckpoint = nil
        defer {
            isRunning = false
            activeDeviceID = nil
            activeUnitID = nil
            activeCheckpoint = nil
        }

        do {
            emit(.gettingInfo, observer: observer)
            let installed = try await readDeviceInformation(unitID: unitID)
            emit(.fetchingManifest, installed: installed.firmwareVersion, observer: observer)
            let signed = try await network.fetchSignedManifest(
                channel: channel,
                variant: installed.variant == "ja" ? "ja" : "multilingual"
            )
            try checkCancellation()

            emit(.validatingManifest, installed: installed.firmwareVersion, observer: observer)
            try signatureVerifier.verify(
                message: signed.manifestBytes,
                detachedSignature: signed.detachedSignature,
                keyID: signed.keyID
            )
            let manifest: OTAManifest
            do { manifest = try JSONDecoder().decode(OTAManifest.self, from: signed.manifestBytes) } catch {
                throw OTAFailure.invalidManifest("Manifest JSON does not match schema")
            }
            try validate(manifest: manifest, for: installed)

            if manifest.secureVersion == installed.secureVersion {
                if let checkpoint = try? await checkpointStore.load(deviceID: deviceID),
                    checkpoint.matchesTarget(deviceID: deviceID, manifest: manifest)
                {
                    try? await checkpointStore.remove(deviceID: deviceID)
                }
                return emit(
                    .upToDate,
                    installed: installed.firmwareVersion,
                    target: manifest.versionName,
                    observer: observer
                )
            }

            emit(
                .downloading,
                total: manifest.size,
                installed: installed.firmwareVersion,
                target: manifest.versionName,
                observer: observer
            )
            let artifact = try await network.fetchArtifact(
                from: manifest.downloadURL,
                maximumBytes: min(policy.maximumArtifactBytes, manifest.size)
            )
            try checkCancellation()
            emit(
                .validatingArtifact,
                total: manifest.size,
                installed: installed.firmwareVersion,
                target: manifest.versionName,
                observer: observer
            )
            try validate(artifact: artifact, manifest: manifest)

            var checkpoint = try await checkpointStore.load(deviceID: deviceID)
            if checkpoint?.matches(
                deviceID: deviceID,
                manifest: manifest,
                entityTag: artifact.entityTag
            ) != true {
                checkpoint = OTACheckpoint(deviceID: deviceID, manifest: manifest, entityTag: artifact.entityTag)
                try await checkpointStore.save(checkpoint!)
            }
            activeCheckpoint = checkpoint

            if checkpoint!.resolvedCommitState == .requestOutcomeUnknown {
                checkpoint = try await reconcileUnknownCommit(
                    checkpoint: checkpoint!,
                    manifest: manifest,
                    unitID: unitID
                )
                activeCheckpoint = checkpoint
            }

            if checkpoint!.resolvedCommitState != .requestOutcomeUnknown,
                checkpoint!.resolvedCommitState != .confirmed
            {
                emit(
                    .preparing,
                    total: manifest.size,
                    installed: installed.firmwareVersion,
                    target: manifest.versionName,
                    observer: observer
                )
                let startOffset = try await prepareBLETransfer(
                    checkpoint: checkpoint!,
                    manifest: manifest,
                    unitID: unitID
                )
                checkpoint!.confirmedOffset = startOffset
                try await checkpointStore.save(checkpoint!)
                activeCheckpoint = checkpoint
                checkpoint = try await transfer(
                    artifact: artifact.bytes,
                    manifest: manifest,
                    checkpoint: checkpoint!,
                    unitID: unitID,
                    installedVersion: installed.firmwareVersion,
                    observer: observer
                )
                try await waitUntilVerified(
                    unitID: unitID,
                    manifest: manifest,
                    installedVersion: installed.firmwareVersion,
                    observer: observer
                )
                checkpoint!.didCommit = false
                checkpoint!.commitState = .verified
                try await checkpointStore.save(checkpoint!)
                activeCheckpoint = checkpoint
                emit(
                    .committing,
                    confirmed: manifest.size,
                    total: manifest.size,
                    installed: installed.firmwareVersion,
                    target: manifest.versionName,
                    observer: observer
                )
                // Persist the ambiguous in-flight state before COMMIT. If the
                // process stops during the request, the next workflow must
                // reconcile with the device instead of blindly committing
                // again. A definitive local/pre-send error restores VERIFIED.
                checkpoint!.didCommit = true
                checkpoint!.commitState = .requestOutcomeUnknown
                try await checkpointStore.save(checkpoint!)
                activeCheckpoint = checkpoint
                do {
                    let commitResult = try await commitOnce(unitID: unitID)
                    checkpoint!.commitState = commitResult.checkpointState
                    try await checkpointStore.save(checkpoint!)
                    activeCheckpoint = checkpoint
                } catch {
                    checkpoint!.didCommit = false
                    checkpoint!.commitState = .verified
                    try await checkpointStore.save(checkpoint!)
                    activeCheckpoint = checkpoint
                    throw error
                }
            }

            emit(
                .reconnecting,
                confirmed: manifest.size,
                total: manifest.size,
                installed: installed.firmwareVersion,
                target: manifest.versionName,
                observer: observer
            )
            let updated = try await confirmInstalledVersion(
                expected: manifest.versionName,
                unitID: unitID,
                observer: observer,
                total: manifest.size
            )
            try await checkpointStore.remove(deviceID: deviceID)
            activeCheckpoint = nil
            return emit(
                .succeeded,
                confirmed: manifest.size,
                total: manifest.size,
                installed: updated.firmwareVersion,
                target: manifest.versionName,
                observer: observer
            )
        } catch is CancellationError {
            _ = emit(.cancelled, observer: observer)
            throw OTAFailure.cancelled
        } catch OTAFailure.cancelled {
            _ = emit(.cancelled, observer: observer)
            throw OTAFailure.cancelled
        } catch {
            _ = emit(.failed, observer: observer)
            throw map(error)
        }
    }

    public func cancel() async {
        cancellationRequested = true
        await bestEffortCancel()
        _ = emit(.cancelled, observer: { _ in })
    }

    private func readDeviceInformation(unitID: UInt8) async throws -> OTADeviceInformation {
        let response = try await transactWithReconnect(
            try OTAProtocolCodec.getInfoRequest(unitID: unitID)
        )
        return try OTAResponseCodec.deviceInformation(response, unitID: unitID)
    }

    private func validate(manifest: OTAManifest, for device: OTADeviceInformation) throws {
        guard manifest.schema == 1 else { throw OTAFailure.invalidManifest("Unsupported schema") }
        guard manifest.monotonicVersion == manifest.secureVersion else {
            throw OTAFailure.invalidManifest("monotonicVersion and secureVersion differ")
        }
        guard manifest.size > 0 else { throw OTAFailure.invalidManifest("Artifact size must be positive") }
        guard manifest.size <= policy.maximumArtifactBytes else {
            throw OTAFailure.artifactTooLarge(manifest.size)
        }
        guard manifest.size <= UInt64(UInt32.max) else { throw OTAFailure.artifactTooLarge(manifest.size) }
        _ = try OTADigest.bytes(fromHex: manifest.sha256)
        guard manifest.downloadURL.scheme?.lowercased() == "https" else { throw OTAFailure.insecureURL }
        guard let host = manifest.downloadURL.host?.lowercased(), allowedArtifactHosts.contains(host) else {
            throw OTAFailure.untrustedHost(manifest.downloadURL.host ?? "")
        }
        guard manifest.downloadURL.user == nil, manifest.downloadURL.password == nil else {
            throw OTAFailure.invalidManifest("Artifact URL must not contain credentials")
        }
        guard manifest.minimumAppVersion <= appVersion else {
            throw OTAFailure.appUpgradeRequired(minimumVersion: manifest.minimumAppVersion)
        }
        guard device.protocolVersion >= 2 else {
            throw OTAFailure.incompatibleProtocol(actual: device.protocolVersion)
        }
        guard device.capabilities & OTAProtocolCodec.bleOTACapability != 0 else {
            throw OTAFailure.unsupportedBLEOTA
        }
        guard device.layoutVersion == manifest.layoutVersion else {
            throw OTAFailure.incompatibleLayout(device: device.layoutVersion, manifest: manifest.layoutVersion)
        }
        guard device.assetPackVersion == manifest.assetPackVersion else {
            throw OTAFailure.incompatibleAssetPack(
                device: device.assetPackVersion,
                manifest: manifest.assetPackVersion
            )
        }
        guard device.variant == manifest.variant else {
            throw OTAFailure.incompatibleVariant(device: device.variant, manifest: manifest.variant)
        }
        guard manifest.secureVersion >= device.secureVersion else {
            throw OTAFailure.secureVersionRollback(
                device: device.secureVersion,
                manifest: manifest.secureVersion
            )
        }
    }

    private func validate(artifact: OTAArtifact, manifest: OTAManifest) throws {
        guard artifact.sourceURL == manifest.downloadURL else {
            throw OTAFailure.invalidManifest("Artifact source URL changed")
        }
        guard UInt64(artifact.bytes.count) == manifest.size else {
            throw OTAFailure.artifactSizeMismatch(
                expected: manifest.size,
                actual: UInt64(artifact.bytes.count)
            )
        }
        guard OTADigest.sha256Hex(artifact.bytes) == manifest.sha256.lowercased() else {
            throw OTAFailure.artifactHashMismatch
        }
    }

    private func prepareBLETransfer(
        checkpoint: OTACheckpoint,
        manifest: OTAManifest,
        unitID: UInt8
    ) async throws -> UInt32 {
        if checkpoint.confirmedOffset > 0,
            let status = try? await readStatus(unitID: unitID),
            status.expectedBytes == UInt32(manifest.size)
        {
            switch status.state {
            case .receiving where status.receivedBytes <= UInt32(manifest.size),
                .verifying where status.receivedBytes <= UInt32(manifest.size):
                // The device is authoritative after a restart. A local
                // checkpoint may be either ahead (save/flash ordering) or
                // behind (ACK received but checkpoint save was interrupted).
                return status.receivedBytes
            case .verified where status.receivedBytes == UInt32(manifest.size):
                return status.receivedBytes
            default:
                break
            }
        }

        let request = try OTAProtocolCodec.bleBeginRequest(
            unitID: unitID,
            expectedBytes: UInt32(manifest.size),
            layoutVersion: manifest.layoutVersion,
            sha256: try OTADigest.bytes(fromHex: manifest.sha256)
        )
        let response = try await transactWithReconnect(request)
        try OTAResponseCodec.empty(response, command: .bleBegin, unitID: unitID)
        return 0
    }

    private func transfer(
        artifact: Data,
        manifest: OTAManifest,
        checkpoint: OTACheckpoint,
        unitID: UInt8,
        installedVersion: String,
        observer: @escaping Observer
    ) async throws -> OTACheckpoint {
        let transportLimit = try await transport.maximumFirmwareChunkByteCount()
        let chunkSize = min(OTAProtocolCodec.maximumFirmwareDataByteCount, transportLimit)
        guard chunkSize > 0 else { throw OTAFailure.invalidWriteCapacity(transportLimit) }
        var checkpoint = checkpoint
        var offset = Int(checkpoint.confirmedOffset)
        guard offset <= artifact.count else {
            throw OTAFailure.protocolViolation("Checkpoint exceeds artifact")
        }

        while offset < artifact.count {
            try checkCancellation()
            let end = min(offset + chunkSize, artifact.count)
            let chunk = artifact.subdata(in: offset..<end)
            let expected = UInt32(end)
            let acknowledged = try await sendChunk(
                chunk,
                offset: UInt32(offset),
                expectedAcknowledgement: expected,
                unitID: unitID,
                manifestSize: UInt32(manifest.size)
            )
            guard acknowledged == expected else {
                throw OTAFailure.invalidAcknowledgedOffset(expected: expected, actual: acknowledged)
            }
            checkpoint.confirmedOffset = acknowledged
            try await checkpointStore.save(checkpoint)
            activeCheckpoint = checkpoint
            offset = Int(acknowledged)
            emit(
                .transferring,
                confirmed: UInt64(acknowledged),
                total: manifest.size,
                installed: installedVersion,
                target: manifest.versionName,
                observer: observer
            )
        }
        return checkpoint
    }

    private func sendChunk(
        _ chunk: Data,
        offset: UInt32,
        expectedAcknowledgement: UInt32,
        unitID: UInt8,
        manifestSize: UInt32
    ) async throws -> UInt32 {
        let request = try OTAProtocolCodec.bleDataRequest(
            unitID: unitID,
            offset: offset,
            firmwareData: chunk
        )
        var lastError: (any Error)?
        for attempt in 0..<policy.maximumChunkAttempts {
            try checkCancellation()
            do {
                let response = try await transport.transact(request, timeout: policy.commandTimeout)
                return try OTAResponseCodec.acknowledgedOffset(response, unitID: unitID)
            } catch {
                lastError = error
                guard attempt + 1 < policy.maximumChunkAttempts, isRetryable(error) else { break }
                try await reconnect()
                if let status = try? await readStatus(unitID: unitID) {
                    guard status.expectedBytes == manifestSize, status.state == .receiving else {
                        throw OTAFailure.disconnected
                    }
                    if status.receivedBytes >= expectedAcknowledgement {
                        return expectedAcknowledgement
                    }
                }
            }
        }
        throw map(lastError ?? OTAFailure.responseTimedOut)
    }

    private func waitUntilVerified(
        unitID: UInt8,
        manifest: OTAManifest,
        installedVersion: String,
        observer: @escaping Observer
    ) async throws {
        emit(
            .verifying,
            confirmed: manifest.size,
            total: manifest.size,
            installed: installedVersion,
            target: manifest.versionName,
            observer: observer
        )
        for poll in 0..<policy.maximumVerificationPolls {
            try checkCancellation()
            let status = try await readStatus(unitID: unitID)
            switch status.state {
            case .verified: return
            case .failed: throw OTAFailure.deviceVerificationFailed(status.errorCode)
            case .waiting where poll > 0:
                throw OTAFailure.protocolViolation("Device discarded the OTA session")
            case .waiting, .receiving, .verifying, .rebooting:
                if poll + 1 < policy.maximumVerificationPolls {
                    try await sleeper.sleep(policy.verificationPollDelay)
                }
            }
        }
        throw OTAFailure.verificationTimedOut
    }

    private func readStatus(unitID: UInt8) async throws -> OTABLEStatus {
        let request = try OTAProtocolCodec.bleStatusRequest(unitID: unitID)
        let response = try await transactWithReconnect(request)
        return try OTAResponseCodec.status(response, unitID: unitID)
    }

    private enum CommitRequestResult {
        case confirmed
        case outcomeUnknown

        var checkpointState: OTACommitCheckpointState {
            switch self {
            case .confirmed: .confirmed
            case .outcomeUnknown: .requestOutcomeUnknown
            }
        }
    }

    private func reconcileUnknownCommit(
        checkpoint: OTACheckpoint,
        manifest: OTAManifest,
        unitID: UInt8
    ) async throws -> OTACheckpoint {
        guard let status = try? await readStatus(unitID: unitID),
            status.expectedBytes == UInt32(manifest.size)
        else {
            // The device may already be rebooting. Preserve the unknown state
            // and proceed to bounded reconnect/version confirmation.
            return checkpoint
        }
        var checkpoint = checkpoint
        switch status.state {
        case .verified:
            // The device is still waiting for COMMIT, proving that a retry is
            // necessary and safe.
            checkpoint.didCommit = false
            checkpoint.commitState = .verified
        case .rebooting:
            checkpoint.didCommit = true
            checkpoint.commitState = .requestOutcomeUnknown
        case .waiting, .receiving, .verifying, .failed:
            // The prior COMMIT did not produce a reboot. Reconcile from live
            // transfer state instead of permanently skipping the operation.
            checkpoint.didCommit = false
            checkpoint.commitState = nil
        }
        try await checkpointStore.save(checkpoint)
        return checkpoint
    }

    private func commitOnce(unitID: UInt8) async throws -> CommitRequestResult {
        let request = try OTAProtocolCodec.bleCommitRequest(unitID: unitID)
        do {
            let response = try await transport.transact(request, timeout: policy.commandTimeout)
            try OTAResponseCodec.empty(response, command: .bleCommit, unitID: unitID)
            return .confirmed
        } catch {
            // A successful commit reboots immediately, so response loss is expected.
            guard isRetryable(error) else { throw map(error) }
            return .outcomeUnknown
        }
    }

    private func confirmInstalledVersion(
        expected: String,
        unitID: UInt8,
        observer: @escaping Observer,
        total: UInt64
    ) async throws -> OTADeviceInformation {
        var didReconnect = false
        for attempt in 0...policy.maximumReconnectAttempts {
            try checkCancellation()
            do {
                try await transport.reconnectAndWait(timeout: policy.reconnectTimeout)
                didReconnect = true
                emit(.confirmingVersion, confirmed: total, total: total, target: expected, observer: observer)
                let info = try await readDeviceInformation(unitID: unitID)
                guard info.firmwareVersion == expected else {
                    throw OTAFailure.installedVersionUnchanged(
                        expected: expected,
                        actual: info.firmwareVersion
                    )
                }
                return info
            } catch let failure as OTAFailure {
                if case .installedVersionUnchanged = failure { throw failure }
                if attempt == policy.maximumReconnectAttempts { break }
            } catch {
                if attempt == policy.maximumReconnectAttempts { break }
            }
        }
        throw didReconnect ? OTAFailure.committedDeviceDidNotReturn : OTAFailure.reconnectFailed
    }

    private func transactWithReconnect(_ request: Data) async throws -> Data {
        var lastError: (any Error)?
        for attempt in 0...policy.maximumReconnectAttempts {
            try checkCancellation()
            do { return try await transport.transact(request, timeout: policy.commandTimeout) } catch {
                lastError = error
                guard attempt < policy.maximumReconnectAttempts, isRetryable(error) else { break }
                try await reconnect()
            }
        }
        throw map(lastError ?? OTAFailure.responseTimedOut)
    }

    private func reconnect() async throws {
        do { try await transport.reconnectAndWait(timeout: policy.reconnectTimeout) } catch { throw OTAFailure.reconnectFailed }
    }

    private func bestEffortCancel() async {
        guard let unitID = activeUnitID, activeCheckpoint?.didCommit != true else { return }
        if let request = try? OTAProtocolCodec.bleCancelRequest(unitID: unitID),
            let response = try? await transport.transact(request, timeout: policy.commandTimeout)
        {
            try? OTAResponseCodec.empty(response, command: .bleCancel, unitID: unitID)
        }
        if let activeDeviceID { try? await checkpointStore.remove(deviceID: activeDeviceID) }
        activeCheckpoint = nil
    }

    private func checkCancellation() throws {
        if cancellationRequested { throw OTAFailure.cancelled }
        try Task.checkCancellation()
    }

    private func isRetryable(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? OTAFailure {
            return failure == .disconnected || failure == .responseTimedOut || failure == .reconnectFailed
        }
        if let failure = error as? BluetoothFailure {
            return failure.code == .disconnected || failure.code == .responseTimeout || failure.code == .staleConnection
                || failure.code == .notReady
        }
        return false
    }

    private func map(_ error: any Error) -> OTAFailure {
        if let failure = error as? OTAFailure { return failure }
        if error is CancellationError { return .cancelled }
        if let failure = error as? BluetoothFailure {
            switch failure.code {
            case .disconnected, .staleConnection, .notReady: return .disconnected
            case .responseTimeout, .writeFailed: return .responseTimedOut
            default: return .protocolViolation(failure.detail)
            }
        }
        return .protocolViolation(String(describing: error))
    }

    @discardableResult
    private func emit(
        _ stage: OTAWorkflowStage,
        confirmed: UInt64 = 0,
        total: UInt64 = 0,
        installed: String? = nil,
        target: String? = nil,
        observer: Observer
    ) -> OTAWorkflowSnapshot {
        current = OTAWorkflowSnapshot(
            stage: stage,
            confirmedBytes: confirmed,
            totalBytes: total,
            installedVersion: installed ?? current.installedVersion,
            targetVersion: target ?? current.targetVersion
        )
        observer(current)
        return current
    }
}
