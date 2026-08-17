import Foundation
import Testing

@testable import MauryaShare

struct ShareWorkflowTests {
    @Test func createModeratesUploadsAndProducesCanonicalQR() async throws {
        let created = try createdShare()
        let remote = FakeShareRemote(createResult: .success(created), fetchResult: .failure(.transport))
        let workflow = ShareWorkflow(
            remote: remote,
            effectConsumer: FakeEffectConsumer(),
            paletteConsumer: FakePaletteConsumer()
        )
        let result = try await workflow.create(try safeEffectEnvelope())

        #expect(result == created)
        #expect(await remote.createdEnvelopes.count == 1)
        guard case let .created(stateCreated, descriptor) = await workflow.state else {
            Issue.record("Expected created state")
            return
        }
        #expect(stateCreated == created)
        #expect(descriptor.payload == created.shareURL.absoluteString)
        #expect(descriptor.errorCorrection == .high)
    }

    @Test func rejectedCreateNeverUploads() async throws {
        let remote = FakeShareRemote(createResult: .success(try createdShare()), fetchResult: .failure(.transport))
        let workflow = ShareWorkflow(
            remote: remote,
            effectConsumer: FakeEffectConsumer(),
            paletteConsumer: FakePaletteConsumer()
        )
        let rejected = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "六四事件", ja: ""),
            sourceKind: .script,
            source: "effect \"safe\" { wait(1s); }"
        )

        await #expect(throws: ShareWorkflowFailure.moderationRejected) {
            try await workflow.create(rejected)
        }
        #expect(await remote.createdEnvelopes.isEmpty)
    }

    @Test func effectPreviewConflictAndAtomicConfirmFlow() async throws {
        let pending = try effectPending()
        let consumer = FakeEffectConsumer(
            previewValue: ShareConsumerPreview(
                resourceCount: 7,
                warnings: ["local warning"],
                conflicts: [.nameCollision("安全")]
            )
        )
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .success(pending)),
            effectConsumer: consumer,
            paletteConsumer: FakePaletteConsumer(),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        let preview = try await workflow.fetchForPreview("K8F3Q-7D2PX")
        #expect(preview.consumer.resourceCount == 7)
        #expect(preview.consumer.warnings == ["local warning"])
        #expect(preview.consumer.conflicts == [.nameCollision("安全")])

        let completed = try await workflow.confirmImport()
        #expect(completed.kind == .effect)
        #expect(completed.localID == "effect-local-id")
        let committed = await consumer.committedRequests
        let request = try #require(committed.first)
        #expect(request.token == "K8F3Q7D2PX")
        #expect(request.importedAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(await consumer.historyMarkers == [request.tokenHash])
        #expect(await workflow.state == .imported(completed))
    }

    @Test func paletteUsesPaletteConsumerOnly() async throws {
        let pending = try palettePending()
        let effect = FakeEffectConsumer()
        let palette = FakePaletteConsumer()
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .success(pending)),
            effectConsumer: effect,
            paletteConsumer: palette
        )

        _ = try await workflow.fetchForPreview(pending.token)
        let completed = try await workflow.confirmImport()
        #expect(completed.kind == .palette)
        #expect(await palette.committedRequests.count == 1)
        #expect(await effect.committedRequests.isEmpty)
    }

    @Test func duplicateTokenRemainsPreviewAndNeverCommits() async throws {
        let pending = try effectPending()
        let effect = FakeEffectConsumer(imported: true)
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .success(pending)),
            effectConsumer: effect,
            paletteConsumer: FakePaletteConsumer()
        )

        let preview = try await workflow.fetchForPreview(pending.token)
        #expect(preview.isAlreadyImported)
        await #expect(throws: ShareWorkflowFailure.duplicateToken) {
            try await workflow.confirmImport()
        }
        #expect(await effect.committedRequests.isEmpty)
        guard case let .preview(_, failure) = await workflow.state else {
            Issue.record("Expected preview state after duplicate rejection")
            return
        }
        #expect(failure == .duplicateToken)
    }

    @Test func confirmRechecksHistoryAfterPreview() async throws {
        let pending = try effectPending()
        let effect = FakeEffectConsumer()
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .success(pending)),
            effectConsumer: effect,
            paletteConsumer: FakePaletteConsumer()
        )
        _ = try await workflow.fetchForPreview(pending.token)
        await effect.setImported(true)

        await #expect(throws: ShareWorkflowFailure.duplicateToken) {
            try await workflow.confirmImport()
        }
        #expect(await effect.committedRequests.isEmpty)
    }

    @Test func atomicMarkerCollisionIsMappedToDuplicateAndRollsBack() async throws {
        let pending = try effectPending()
        let effect = FakeEffectConsumer(duplicateOnImport: true)
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .success(pending)),
            effectConsumer: effect,
            paletteConsumer: FakePaletteConsumer()
        )
        _ = try await workflow.fetchForPreview(pending.token)

        await #expect(throws: ShareWorkflowFailure.duplicateToken) {
            try await workflow.confirmImport()
        }
        #expect(await effect.committedRequests.isEmpty)
        #expect(await effect.historyMarkers.isEmpty)
    }

    @Test func failedTransactionRollsBackDomainAndHistoryAndKeepsPreview() async throws {
        let pending = try effectPending()
        let effect = FakeEffectConsumer(failImport: true)
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .success(pending)),
            effectConsumer: effect,
            paletteConsumer: FakePaletteConsumer()
        )
        _ = try await workflow.fetchForPreview(pending.token)

        await #expect(throws: ShareWorkflowFailure.consumer) {
            try await workflow.confirmImport()
        }
        #expect(await effect.committedRequests.isEmpty)
        #expect(await effect.historyMarkers.isEmpty)
        guard case let .preview(_, failure) = await workflow.state else {
            Issue.record("Expected retryable preview state")
            return
        }
        #expect(failure == .consumer)
    }

    @Test func timeoutIsTypedAndDoesNotCreatePreview() async throws {
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(createResult: .failure(.transport), fetchResult: .failure(.timedOut)),
            effectConsumer: FakeEffectConsumer(),
            paletteConsumer: FakePaletteConsumer()
        )
        await #expect(throws: ShareWorkflowFailure.remote(.timedOut)) {
            try await workflow.fetchForPreview("K8F3Q7D2PX")
        }
        #expect(await workflow.state == .failed(.remote(.timedOut)))
    }

    @Test func explicitCancelInvalidatesInFlightResultWithoutStaleOverwrite() async throws {
        let gate = AsyncGate()
        let remote = FakeShareRemote(
            createResult: .failure(.transport),
            fetchResult: .success(try effectPending()),
            fetchGate: gate
        )
        let workflow = ShareWorkflow(
            remote: remote,
            effectConsumer: FakeEffectConsumer(),
            paletteConsumer: FakePaletteConsumer()
        )
        let task = Task { try await workflow.fetchForPreview("K8F3Q7D2PX") }
        await gate.waitUntilEntered()
        await workflow.cancel()
        await gate.release()

        await #expect(throws: ShareWorkflowFailure.staleOperation) {
            try await task.value
        }
        #expect(await workflow.state == .cancelled)
    }

    @Test func invalidSecondTokenCannotOverwriteInFlightFetchState() async throws {
        let gate = AsyncGate()
        let pending = try effectPending()
        let workflow = ShareWorkflow(
            remote: FakeShareRemote(
                createResult: .failure(.transport),
                fetchResult: .success(pending),
                fetchGate: gate
            ),
            effectConsumer: FakeEffectConsumer(),
            paletteConsumer: FakePaletteConsumer()
        )
        let first = Task { try await workflow.fetchForPreview(pending.token) }
        await gate.waitUntilEntered()

        await #expect(throws: ShareWorkflowFailure.busy) {
            try await workflow.fetchForPreview("not-a-token")
        }
        #expect(await workflow.state == .fetching(token: pending.token))

        await gate.release()
        #expect(try await first.value.pending.token == pending.token)
        guard case .preview = await workflow.state else {
            Issue.record("Expected first fetch to retain ownership of workflow state")
            return
        }
    }
}

private enum FakeConsumerError: Error { case failed }

private actor FakeShareRemote: ShareRemoteServing {
    let createResult: Result<CreatedShare, ShareAPIError>
    let fetchResult: Result<PendingShareImport, ShareAPIError>
    let fetchGate: AsyncGate?
    private(set) var createdEnvelopes: [ShareEnvelope] = []

    init(
        createResult: Result<CreatedShare, ShareAPIError>,
        fetchResult: Result<PendingShareImport, ShareAPIError>,
        fetchGate: AsyncGate? = nil
    ) {
        self.createResult = createResult
        self.fetchResult = fetchResult
        self.fetchGate = fetchGate
    }

    func create(_ envelope: ShareEnvelope, idempotencyKey: UUID) async throws -> CreatedShare {
        createdEnvelopes.append(envelope)
        return try createResult.get()
    }

    func fetchForPreview(_ rawToken: String) async throws -> PendingShareImport {
        if let fetchGate { await fetchGate.enter() }
        return try fetchResult.get()
    }
}

private actor FakeEffectConsumer: EffectShareImportConsuming {
    private var imported: Bool
    let previewValue: ShareConsumerPreview
    let failImport: Bool
    let duplicateOnImport: Bool
    private(set) var committedRequests: [EffectShareImportRequest] = []
    private(set) var historyMarkers: [String] = []

    init(
        imported: Bool = false,
        previewValue: ShareConsumerPreview = ShareConsumerPreview(resourceCount: 1),
        failImport: Bool = false,
        duplicateOnImport: Bool = false
    ) {
        self.imported = imported
        self.previewValue = previewValue
        self.failImport = failImport
        self.duplicateOnImport = duplicateOnImport
    }

    func wasImported(tokenHash: String) async throws -> Bool { imported }
    func preview(_ request: EffectShareImportRequest) async throws -> ShareConsumerPreview { previewValue }

    func setImported(_ value: Bool) {
        imported = value
    }

    func importAtomically(_ request: EffectShareImportRequest) async throws -> String {
        try Task.checkCancellation()
        if duplicateOnImport { throw ShareImportConsumerError.duplicateToken }
        if failImport { throw FakeConsumerError.failed }
        committedRequests.append(request)
        historyMarkers.append(request.tokenHash)
        return "effect-local-id"
    }
}

private actor FakePaletteConsumer: PaletteShareImportConsuming {
    let imported: Bool
    let previewValue: ShareConsumerPreview
    let failImport: Bool
    private(set) var committedRequests: [PaletteShareImportRequest] = []
    private(set) var historyMarkers: [String] = []

    init(
        imported: Bool = false,
        previewValue: ShareConsumerPreview = ShareConsumerPreview(resourceCount: 1),
        failImport: Bool = false
    ) {
        self.imported = imported
        self.previewValue = previewValue
        self.failImport = failImport
    }

    func wasImported(tokenHash: String) async throws -> Bool { imported }
    func preview(_ request: PaletteShareImportRequest) async throws -> ShareConsumerPreview { previewValue }

    func importAtomically(_ request: PaletteShareImportRequest) async throws -> String {
        try Task.checkCancellation()
        if failImport { throw FakeConsumerError.failed }
        committedRequests.append(request)
        historyMarkers.append(request.tokenHash)
        return "palette-local-id"
    }
}

private actor AsyncGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private func createdShare() throws -> CreatedShare {
    CreatedShare(
        token: "K8F3Q7D2PX",
        shareURL: try #require(URL(string: "https://xtbang.top/maurya/s/K8F3Q7D2PX")),
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        blobSHA256: String(repeating: "a", count: 64),
        moderationVersion: "v1"
    )
}

private func safeEffectEnvelope() throws -> ShareEnvelope {
    try ShareEnvelopeCodec.makeEffect(
        names: ShareDisplayName(zh: "安全", ja: ""),
        sourceKind: .script,
        source: "effect \"safe\" { wait(1s); }"
    )
}

private func effectPending() throws -> PendingShareImport {
    let envelope = try safeEffectEnvelope()
    return PendingShareImport(
        token: "K8F3Q7D2PX",
        metadata: metadata(kind: .effect),
        envelope: envelope
    )
}

private func palettePending() throws -> PendingShareImport {
    let avatar = webP96Fixture()
    let envelope = try ShareEnvelopeCodec.makePalette(
        names: ShareDisplayName(zh: "蓝色", ja: ""),
        hex: "#1122AA",
        avatarWebP: avatar
    )
    return PendingShareImport(
        token: "J8F3Q7D2PX",
        metadata: metadata(kind: .palette),
        envelope: envelope
    )
}

private func metadata(kind: ShareKind) -> ShareMetadata {
    ShareMetadata(
        kind: kind,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 1_700_604_800),
        expiresInSeconds: 604_800,
        compressedBytes: 100,
        blobSHA256: String(repeating: "b", count: 64)
    )
}

private func webP96Fixture() -> Data {
    var bytes = Data(repeating: 0, count: 30)
    bytes.replaceSubrange(0..<4, with: Data("RIFF".utf8))
    var RIFFSize = UInt32(22).littleEndian
    withUnsafeBytes(of: &RIFFSize) { bytes.replaceSubrange(4..<8, with: $0) }
    bytes.replaceSubrange(8..<12, with: Data("WEBP".utf8))
    bytes.replaceSubrange(12..<16, with: Data("VP8X".utf8))
    var chunkSize = UInt32(10).littleEndian
    withUnsafeBytes(of: &chunkSize) { bytes.replaceSubrange(16..<20, with: $0) }
    bytes[24] = 95
    bytes[27] = 95
    return bytes
}
