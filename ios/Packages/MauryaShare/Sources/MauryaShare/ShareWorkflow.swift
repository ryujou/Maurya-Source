import Foundation

public protocol ShareRemoteServing: Sendable {
    func create(_ envelope: ShareEnvelope, idempotencyKey: UUID) async throws -> CreatedShare
    func fetchForPreview(_ rawToken: String) async throws -> PendingShareImport
}

public protocol ShareQRCodeDescribing: Sendable {
    func descriptor(for shareURL: URL) throws -> ShareQRCodeDescriptor
}

public struct DefaultShareQRCodeDescriber: ShareQRCodeDescribing, Sendable {
    public init() {}

    public func descriptor(for shareURL: URL) throws -> ShareQRCodeDescriptor {
        try ShareQRCodeDescriptor(payload: shareURL.absoluteString)
    }
}

public enum ShareImportConflict: Sendable, Equatable {
    case alreadyImported
    case nameCollision(String)
    case incompatible(String)
}

public struct ShareConsumerPreview: Sendable, Equatable {
    public let resourceCount: Int
    public let warnings: [String]
    public let conflicts: [ShareImportConflict]

    public init(resourceCount: Int, warnings: [String] = [], conflicts: [ShareImportConflict] = []) {
        self.resourceCount = resourceCount
        self.warnings = warnings
        self.conflicts = conflicts
    }
}

public struct ShareImportPreview: Sendable, Equatable {
    public let pending: PendingShareImport
    public let consumer: ShareConsumerPreview

    public var isAlreadyImported: Bool { consumer.conflicts.contains(.alreadyImported) }
}

public struct EffectShareImportRequest: Sendable, Equatable {
    public let token: String
    public let tokenHash: String
    public let metadata: ShareMetadata
    public let displayName: ShareDisplayName
    public let payload: EffectSharePayload
    public let importedAt: Date
}

public struct PaletteShareImportRequest: Sendable, Equatable {
    public let token: String
    public let tokenHash: String
    public let metadata: ShareMetadata
    public let displayName: ShareDisplayName
    public let payload: PaletteSharePayload
    public let importedAt: Date
}

public enum ShareImportConsumerError: Error, Sendable, Equatable {
    case duplicateToken
    case transactionFailed
}

public protocol EffectShareImportConsuming: Sendable {
    func wasImported(tokenHash: String) async throws -> Bool
    func preview(_ request: EffectShareImportRequest) async throws -> ShareConsumerPreview

    /// Must write the effect and a uniquely constrained token-history marker
    /// in one transaction. A marker collision throws `.duplicateToken`.
    /// Any other throw or cancellation must leave neither write visible.
    func importAtomically(_ request: EffectShareImportRequest) async throws -> String
}

public protocol PaletteShareImportConsuming: Sendable {
    func wasImported(tokenHash: String) async throws -> Bool
    func preview(_ request: PaletteShareImportRequest) async throws -> ShareConsumerPreview

    /// Must write the palette and a uniquely constrained token-history marker
    /// in one transaction. A marker collision throws `.duplicateToken`.
    /// Any other throw or cancellation must leave neither write visible.
    func importAtomically(_ request: PaletteShareImportRequest) async throws -> String
}

public struct CompletedShareImport: Sendable, Equatable {
    public let token: String
    public let kind: ShareKind
    public let localID: String
}

public enum ShareWorkflowFailure: Error, Sendable, Equatable {
    case busy
    case noPreview
    case duplicateToken
    case moderationRejected
    case remote(ShareAPIError)
    case validation(ShareValidationError)
    case consumer
    case cancelled
    case staleOperation
}

public enum ShareWorkflowState: Sendable, Equatable {
    case idle
    case creating
    case created(CreatedShare, ShareQRCodeDescriptor)
    case fetching(token: String)
    case preview(ShareImportPreview, lastFailure: ShareWorkflowFailure?)
    case importing(token: String)
    case imported(CompletedShareImport)
    case failed(ShareWorkflowFailure)
    case cancelled
}

public actor ShareWorkflow {
    private let remote: any ShareRemoteServing
    private let effectConsumer: any EffectShareImportConsuming
    private let paletteConsumer: any PaletteShareImportConsuming
    private let QRDescriber: any ShareQRCodeDescribing
    private let now: @Sendable () -> Date
    private var operationGeneration = 0

    public private(set) var state: ShareWorkflowState = .idle

    public init(
        remote: any ShareRemoteServing,
        effectConsumer: any EffectShareImportConsuming,
        paletteConsumer: any PaletteShareImportConsuming,
        QRDescriber: any ShareQRCodeDescribing = DefaultShareQRCodeDescriber(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.remote = remote
        self.effectConsumer = effectConsumer
        self.paletteConsumer = paletteConsumer
        self.QRDescriber = QRDescriber
        self.now = now
    }

    @discardableResult
    public func create(
        _ envelope: ShareEnvelope,
        idempotencyKey: UUID = UUID()
    ) async throws -> CreatedShare {
        let generation = try begin(state: .creating)
        do {
            guard ShareModeration.check(envelope) == .accepted else {
                throw ShareWorkflowFailure.moderationRejected
            }
            try Task.checkCancellation()
            let created = try await remote.create(envelope, idempotencyKey: idempotencyKey)
            try ensureCurrent(generation)
            try Task.checkCancellation()
            let descriptor = try QRDescriber.descriptor(for: created.shareURL)
            try ensureCurrent(generation)
            state = .created(created, descriptor)
            return created
        } catch {
            throw finishFailure(error, generation: generation, preview: nil)
        }
    }

    @discardableResult
    public func fetchForPreview(_ rawToken: String) async throws -> ShareImportPreview {
        // Parsing has no suspension point, but the actor is re-entrant while a
        // remote fetch is awaiting. Reject first so an invalid second token
        // cannot replace an in-flight operation's state with `.failed`.
        try ensureNotBusy()
        let token: String
        do {
            token = try ShareToken.parse(rawToken)
        } catch let error as ShareValidationError {
            state = .failed(.validation(error))
            throw ShareWorkflowFailure.validation(error)
        }
        let generation = try begin(state: .fetching(token: token))
        do {
            try Task.checkCancellation()
            let pending = try await remote.fetchForPreview(token)
            try ensureCurrent(generation)
            guard ShareModeration.check(pending.envelope) == .accepted else {
                throw ShareWorkflowFailure.moderationRejected
            }
            let preview = try await preparePreview(pending)
            try ensureCurrent(generation)
            try Task.checkCancellation()
            state = .preview(preview, lastFailure: nil)
            return preview
        } catch {
            throw finishFailure(error, generation: generation, preview: nil)
        }
    }

    @discardableResult
    public func confirmImport() async throws -> CompletedShareImport {
        guard case let .preview(preview, _) = state else { throw ShareWorkflowFailure.noPreview }
        guard preview.isAlreadyImported == false else {
            state = .preview(preview, lastFailure: .duplicateToken)
            throw ShareWorkflowFailure.duplicateToken
        }
        let generation = try begin(state: .importing(token: preview.pending.token))
        do {
            try Task.checkCancellation()
            let duplicate: Bool
            switch preview.pending.envelope.kind {
            case .effect:
                duplicate = try await effectConsumer.wasImported(
                    tokenHash: Self.tokenHash(preview.pending.token)
                )
            case .palette:
                duplicate = try await paletteConsumer.wasImported(
                    tokenHash: Self.tokenHash(preview.pending.token)
                )
            }
            try ensureCurrent(generation)
            guard duplicate == false else { throw ShareWorkflowFailure.duplicateToken }
            try Task.checkCancellation()
            let importedAt = now()
            let localID: String
            switch preview.pending.envelope.payload {
            case let .effect(payload):
                localID = try await effectConsumer.importAtomically(
                    effectRequest(preview.pending, payload: payload, importedAt: importedAt)
                )
            case let .palette(payload):
                localID = try await paletteConsumer.importAtomically(
                    paletteRequest(preview.pending, payload: payload, importedAt: importedAt)
                )
            }
            try ensureCurrent(generation)
            try Task.checkCancellation()
            guard localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ShareWorkflowFailure.consumer
            }
            let completed = CompletedShareImport(
                token: preview.pending.token,
                kind: preview.pending.envelope.kind,
                localID: localID
            )
            state = .imported(completed)
            return completed
        } catch {
            throw finishFailure(error, generation: generation, preview: preview)
        }
    }

    public func cancel() {
        operationGeneration &+= 1
        state = .cancelled
    }

    public func reset() {
        operationGeneration &+= 1
        state = .idle
    }

    private func preparePreview(_ pending: PendingShareImport) async throws -> ShareImportPreview {
        let tokenHash = Self.tokenHash(pending.token)
        let base: ShareConsumerPreview
        let imported: Bool
        switch pending.envelope.payload {
        case let .effect(payload):
            let request = effectRequest(pending, payload: payload, importedAt: pending.metadata.createdAt)
            imported = try await effectConsumer.wasImported(tokenHash: tokenHash)
            try Task.checkCancellation()
            base = try await effectConsumer.preview(request)
        case let .palette(payload):
            let request = paletteRequest(pending, payload: payload, importedAt: pending.metadata.createdAt)
            imported = try await paletteConsumer.wasImported(tokenHash: tokenHash)
            try Task.checkCancellation()
            base = try await paletteConsumer.preview(request)
        }
        var conflicts = base.conflicts.filter { $0 != .alreadyImported }
        if imported { conflicts.insert(.alreadyImported, at: 0) }
        return ShareImportPreview(
            pending: pending,
            consumer: ShareConsumerPreview(
                resourceCount: base.resourceCount,
                warnings: base.warnings,
                conflicts: conflicts
            )
        )
    }

    private func effectRequest(
        _ pending: PendingShareImport,
        payload: EffectSharePayload,
        importedAt: Date
    ) -> EffectShareImportRequest {
        EffectShareImportRequest(
            token: pending.token,
            tokenHash: Self.tokenHash(pending.token),
            metadata: pending.metadata,
            displayName: pending.envelope.displayName,
            payload: payload,
            importedAt: importedAt
        )
    }

    private func paletteRequest(
        _ pending: PendingShareImport,
        payload: PaletteSharePayload,
        importedAt: Date
    ) -> PaletteShareImportRequest {
        PaletteShareImportRequest(
            token: pending.token,
            tokenHash: Self.tokenHash(pending.token),
            metadata: pending.metadata,
            displayName: pending.envelope.displayName,
            payload: payload,
            importedAt: importedAt
        )
    }

    private func begin(state nextState: ShareWorkflowState) throws -> Int {
        try ensureNotBusy()
        operationGeneration &+= 1
        state = nextState
        return operationGeneration
    }

    private func ensureNotBusy() throws {
        switch state {
        case .creating, .fetching, .importing:
            throw ShareWorkflowFailure.busy
        default:
            return
        }
    }

    private func ensureCurrent(_ generation: Int) throws {
        guard generation == operationGeneration else { throw ShareWorkflowFailure.staleOperation }
    }

    private func finishFailure(
        _ error: any Error,
        generation: Int,
        preview: ShareImportPreview?
    ) -> ShareWorkflowFailure {
        let failure = Self.mapFailure(error)
        guard generation == operationGeneration else { return .staleOperation }
        if failure == .cancelled || failure == .staleOperation {
            state = .cancelled
        } else if let preview {
            state = .preview(preview, lastFailure: failure)
        } else {
            state = .failed(failure)
        }
        return failure
    }

    private static func mapFailure(_ error: any Error) -> ShareWorkflowFailure {
        if let failure = error as? ShareWorkflowFailure { return failure }
        if error is CancellationError { return .cancelled }
        if let APIError = error as? ShareAPIError {
            return APIError == .cancelled ? .cancelled : .remote(APIError)
        }
        if let validation = error as? ShareValidationError { return .validation(validation) }
        if let consumer = error as? ShareImportConsumerError {
            return consumer == .duplicateToken ? .duplicateToken : .consumer
        }
        return .consumer
    }

    private static func tokenHash(_ token: String) -> String {
        ShareEnvelopeCodec.sha256(Data(token.utf8))
    }
}
