import Foundation
import MauryaEffects
import MauryaResources
import MauryaShare
import Observation

@MainActor
@Observable
final class LiveShareImportService: ShareImportService {
    private(set) var validation = ShareImportValidation.idle
    private(set) var section = ShareSection.importShare
    private(set) var operation = ShareOperationState.idle
    private(set) var effects: [ShareEffectChoice] = []
    private(set) var palettes: [SharePaletteChoice] = []

    private let workflow: ShareWorkflow?
    private let effectRepository: (any EffectProgramRepositoryServing)?
    private let paletteRepository: CustomPaletteRepository?

    /// Validation-only initializer retained for deterministic deep-link tests.
    init() {
        workflow = nil
        effectRepository = nil
        paletteRepository = nil
    }

    init(
        workflow: ShareWorkflow,
        effectRepository: any EffectProgramRepositoryServing,
        paletteRepository: CustomPaletteRepository
    ) {
        self.workflow = workflow
        self.effectRepository = effectRepository
        self.paletteRepository = paletteRepository
    }

    static func production(
        effectRepository: any EffectProgramRepositoryServing,
        paletteRepository: CustomPaletteRepository
    ) throws -> LiveShareImportService {
        let history = ShareImportHistory(fileURL: try ShareImportHistory.applicationSupportFile())
        let effectConsumer = EffectShareConsumer(repository: effectRepository, history: history)
        let paletteConsumer = PaletteShareConsumer(repository: paletteRepository, history: history)
        let workflow = ShareWorkflow(
            remote: try ShareAPIClient.production(),
            effectConsumer: effectConsumer,
            paletteConsumer: paletteConsumer
        )
        return LiveShareImportService(
            workflow: workflow,
            effectRepository: effectRepository,
            paletteRepository: paletteRepository
        )
    }

    func validate(_ input: String) {
        do {
            let token = try ShareToken.parse(input)
            let url = try ShareToken.canonicalURL(token)
            validation = .valid(ValidatedShareLink(token: token, canonicalURL: url))
        } catch {
            validation = .invalid
        }
    }

    func show(_ section: ShareSection) {
        self.section = section
        operation = .idle
    }

    func loadChoices() async {
        guard let effectRepository, let paletteRepository else { return }
        do {
            let effectRecords = try await effectRepository.list()
            let paletteSnapshot = try await paletteRepository.loadAndRepair()
            effects = effectRecords.map {
                ShareEffectChoice(
                    id: $0.program.id,
                    names: ShareDisplayName(zh: $0.program.nameZh, ja: $0.program.nameJa),
                    sourceKind: $0.program.sourceKind == .blocks ? "share.kind.blocks" : "share.kind.script"
                )
            }
            palettes = paletteSnapshot.entries.map {
                SharePaletteChoice(
                    id: $0.id,
                    names: ShareDisplayName(zh: $0.names.zh, ja: $0.names.ja),
                    hex: $0.color.rawValue
                )
            }
        } catch is CancellationError {
            return
        } catch {
            operation = .failed(Self.describe(error))
        }
    }

    func createEffect(id: String) async {
        guard let workflow, let effectRepository else {
            operation = .failed("share.service.unavailable")
            return
        }
        operation = .busy
        do {
            guard let program = try await effectRepository.list().first(where: { $0.program.id == id })?.program else {
                throw EffectProgramError.programNotFound(id)
            }
            let sourceKind: MauryaShare.EffectSourceKind = program.sourceKind == .blocks ? .blocks : .script
            let source = program.sourceKind == .blocks ? program.workspaceJSON : program.scriptSource
            let envelope = try ShareEnvelopeCodec.makeEffect(
                names: ShareDisplayName(zh: program.nameZh, ja: program.nameJa),
                sourceKind: sourceKind,
                source: source
            )
            let created = try await workflow.create(envelope)
            guard case let .created(_, descriptor) = await workflow.state else {
                throw ShareWorkflowFailure.staleOperation
            }
            operation = .created(created, descriptor)
        } catch is CancellationError {
            operation = .idle
        } catch {
            operation = .failed(Self.describe(error))
        }
    }

    func createPalette(id: UUID) async {
        guard let workflow, let paletteRepository else {
            operation = .failed("share.service.unavailable")
            return
        }
        operation = .busy
        do {
            let snapshot = try await paletteRepository.snapshot()
            guard let entry = snapshot.entries.first(where: { $0.id == id }) else {
                throw CustomPaletteError.notFound
            }
            let avatar = try await paletteRepository.avatarWebP(id: id)
            let created = try await workflow.create(try entry.makeShareEnvelope(avatarWebP: avatar))
            guard case let .created(_, descriptor) = await workflow.state else {
                throw ShareWorkflowFailure.staleOperation
            }
            operation = .created(created, descriptor)
        } catch is CancellationError {
            operation = .idle
        } catch {
            operation = .failed(Self.describe(error))
        }
    }

    func fetchForPreview(_ input: String) async {
        validate(input)
        guard case let .valid(link) = validation, let workflow else {
            operation = .failed("share.validation.invalid.message")
            return
        }
        operation = .busy
        do {
            operation = .preview(try await workflow.fetchForPreview(link.token))
        } catch is CancellationError {
            operation = .idle
        } catch {
            operation = .failed(Self.describe(error))
        }
    }

    func confirmImport() async {
        guard let workflow else {
            operation = .failed("share.service.unavailable")
            return
        }
        operation = .busy
        do {
            operation = .imported(try await workflow.confirmImport())
            await loadChoices()
        } catch is CancellationError {
            operation = .idle
        } catch {
            operation = .failed(Self.describe(error))
        }
    }

    func cancel() {
        operation = .idle
        Task { await workflow?.cancel() }
    }

    private static func describe(_ error: any Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private actor EffectShareConsumer: EffectShareImportConsuming {
    private let repository: any EffectProgramRepositoryServing
    private let history: ShareImportHistory

    init(repository: any EffectProgramRepositoryServing, history: ShareImportHistory) {
        self.repository = repository
        self.history = history
    }

    func wasImported(tokenHash: String) async throws -> Bool {
        try await history.records().contains { $0.tokenHash == tokenHash }
    }

    func preview(_ request: EffectShareImportRequest) async throws -> ShareConsumerPreview {
        let existing = try await repository.list()
        _ = try makeProgram(request, existing: existing)
        return ShareConsumerPreview(resourceCount: 1)
    }

    func importAtomically(_ request: EffectShareImportRequest) async throws -> String {
        let existing = try await repository.list()
        let program = try makeProgram(request, existing: existing)
        let record = try await repository.upsert(program, expectedRevision: nil)
        do {
            _ = try await history.recordImport(token: request.token, localID: record.program.id, importedAt: request.importedAt)
            return record.program.id
        } catch {
            _ = try? await repository.delete(id: record.program.id, expectedRevision: record.revision)
            throw error
        }
    }

    private func makeProgram(_ request: EffectShareImportRequest, existing: [EffectProgramRecord]) throws -> EffectProgram {
        let timestamp = Int64(request.importedAt.timeIntervalSince1970 * 1_000)
        let sourceKind: MauryaEffects.EffectSourceKind = request.payload.sourceKind == .blocks ? .blocks : .script
        let names = CopyNameResolver.resolve(
            zh: request.displayName.zh,
            ja: request.displayName.ja,
            existingZh: Set(existing.map(\.program.nameZh)),
            existingJa: Set(existing.map(\.program.nameJa)),
            limit: 64
        )
        return try EffectProgramCompiler.normalise(
            EffectProgram(
                id: UUID().uuidString,
                nameZh: names.zh,
                nameJa: names.ja,
                workspaceJSON: sourceKind == .blocks ? request.payload.source : "",
                createdAt: timestamp,
                updatedAt: timestamp,
                sourceKind: sourceKind,
                scriptSource: sourceKind == .script ? request.payload.source : ""
            ),
            now: timestamp
        )
    }
}

private actor PaletteShareConsumer: PaletteShareImportConsuming {
    private let repository: CustomPaletteRepository
    private let history: ShareImportHistory

    init(repository: CustomPaletteRepository, history: ShareImportHistory) {
        self.repository = repository
        self.history = history
    }

    func wasImported(tokenHash: String) async throws -> Bool {
        try await history.records().contains { $0.tokenHash == tokenHash }
    }

    func preview(_ request: PaletteShareImportRequest) async throws -> ShareConsumerPreview {
        _ = try AvatarValidator.validate(
            request.payload.avatarWebP,
            expectedSHA256: request.payload.avatarSHA256
        )
        guard RGBHex(rawValue: request.payload.hex) != nil else { throw CustomPaletteError.invalidColor }
        return ShareConsumerPreview(resourceCount: 1)
    }

    func importAtomically(_ request: PaletteShareImportRequest) async throws -> String {
        let snapshot = try await repository.snapshot()
        let names = CopyNameResolver.resolve(
            zh: request.displayName.zh,
            ja: request.displayName.ja,
            existingZh: Set(snapshot.entries.map(\.names.zh)),
            existingJa: Set(snapshot.entries.map(\.names.ja)),
            limit: 32
        )
        let entry = try await repository.importShare(
            names: ShareDisplayName(zh: names.zh, ja: names.ja),
            payload: request.payload
        )
        do {
            _ = try await history.recordImport(token: request.token, localID: entry.id.uuidString, importedAt: request.importedAt)
            return entry.id.uuidString
        } catch {
            _ = try? await repository.delete(id: entry.id, expectedRevision: entry.revision)
            throw error
        }
    }
}

private enum CopyNameResolver {
    static func resolve(
        zh: String,
        ja: String,
        existingZh: Set<String>,
        existingJa: Set<String>,
        limit: Int
    ) -> (zh: String, ja: String) {
        (
            unique(zh, existing: existingZh, suffix: " 副本", limit: limit),
            unique(ja, existing: existingJa, suffix: " コピー", limit: limit)
        )
    }

    private static func unique(_ original: String, existing: Set<String>, suffix: String, limit: Int) -> String {
        guard original.isEmpty == false, existing.contains(original) else { return original }
        for number in 1...9_999 {
            let resolvedSuffix = number == 1 ? suffix : "\(suffix) \(number)"
            let available = max(0, limit - resolvedSuffix.count)
            let candidate = String(original.prefix(available)).trimmingCharacters(in: .whitespaces) + resolvedSuffix
            if existing.contains(candidate) == false { return candidate }
        }
        return String(UUID().uuidString.prefix(limit))
    }
}
