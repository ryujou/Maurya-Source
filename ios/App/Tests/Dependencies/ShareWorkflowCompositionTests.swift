import Foundation
import MauryaEffects
import MauryaResources
import MauryaShare
import Testing

@testable import Maurya

private let appShareTestToken = "K8F3Q7D2PX"

@MainActor
struct ShareWorkflowCompositionTests {
    @Test func createsSelectedEffectAndPublishesQRCode() async throws {
        let fixture = try Fixture()
        await fixture.service.createEffect(id: "effect-1")

        guard case let .created(created, descriptor) = fixture.service.operation else {
            Issue.record("Expected a created share")
            return
        }
        #expect(created.token == appShareTestToken)
        #expect(descriptor.payload == "https://xtbang.top/maurya/s/\(appShareTestToken)")
        let uploaded = await fixture.remote.lastCreated()
        #expect(uploaded?.kind == .effect)
        guard case let .effect(payload) = uploaded?.payload else {
            Issue.record("Expected an effect envelope")
            return
        }
        #expect(payload.sourceKind == .script)
        #expect(payload.source.contains("wait(1s)"))
    }

    @Test func fetchesVerifiedPreviewThenImportsOnlyAfterConfirmation() async throws {
        let fixture = try Fixture()
        await fixture.service.fetchForPreview(appShareTestToken)
        guard case let .preview(preview) = fixture.service.operation else {
            Issue.record("Expected verified preview")
            return
        }
        #expect(preview.pending.token == appShareTestToken)
        #expect(await fixture.consumer.importCount() == 0)

        await fixture.service.confirmImport()
        guard case let .imported(completed) = fixture.service.operation else {
            Issue.record("Expected completed import")
            return
        }
        #expect(completed.localID == "local-effect")
        #expect(await fixture.consumer.importCount() == 1)
    }

    private struct Fixture {
        let remote: FakeShareRemote
        let consumer: FakeEffectShareConsumer
        let service: LiveShareImportService

        @MainActor init() throws {
            let timestamp: Int64 = 1_700_000_000_000
            let program = EffectProgram(
                id: "effect-1",
                nameZh: "测试灯效",
                nameJa: "テストエフェクト",
                createdAt: timestamp,
                updatedAt: timestamp,
                sourceKind: .script,
                scriptSource: ##"effect "Safe" { wait(1s); }"##
            )
            let effectRepository = FakeShareEffectRepository(program: program)
            let paletteRoot = FileManager.default.temporaryDirectory
                .appending(path: "maurya-share-app-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let paletteRepository = CustomPaletteRepository(
                storage: FileCustomPaletteStorage(rootURL: paletteRoot)
            )
            remote = try FakeShareRemote()
            consumer = FakeEffectShareConsumer()
            let workflow = ShareWorkflow(
                remote: remote,
                effectConsumer: consumer,
                paletteConsumer: FakePaletteShareConsumer()
            )
            service = LiveShareImportService(
                workflow: workflow,
                effectRepository: effectRepository,
                paletteRepository: paletteRepository
            )
        }
    }
}

private actor FakeShareRemote: ShareRemoteServing {
    private var createdEnvelope: ShareEnvelope?
    private let pending: PendingShareImport

    init() throws {
        let envelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "导入灯效", ja: "読込エフェクト"),
            sourceKind: .script,
            source: ##"effect "Import" { wait(1s); }"##
        )
        pending = PendingShareImport(
            token: appShareTestToken,
            metadata: ShareMetadata(
                kind: .effect,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                expiresAt: Date(timeIntervalSince1970: 1_700_604_800),
                expiresInSeconds: 604_800,
                compressedBytes: 128,
                blobSHA256: String(repeating: "a", count: 64)
            ),
            envelope: envelope
        )
    }

    func create(_ envelope: ShareEnvelope, idempotencyKey: UUID) async throws -> CreatedShare {
        createdEnvelope = envelope
        return CreatedShare(
            token: appShareTestToken,
            shareURL: try ShareToken.canonicalURL(appShareTestToken),
            expiresAt: Date(timeIntervalSince1970: 1_700_604_800),
            blobSHA256: String(repeating: "b", count: 64),
            moderationVersion: "test"
        )
    }

    func fetchForPreview(_ rawToken: String) async throws -> PendingShareImport { pending }
    func lastCreated() -> ShareEnvelope? { createdEnvelope }
}

private actor FakeEffectShareConsumer: EffectShareImportConsuming {
    private var imported = 0
    func wasImported(tokenHash: String) async throws -> Bool { false }
    func preview(_ request: EffectShareImportRequest) async throws -> ShareConsumerPreview {
        ShareConsumerPreview(resourceCount: 1)
    }
    func importAtomically(_ request: EffectShareImportRequest) async throws -> String {
        imported += 1
        return "local-effect"
    }
    func importCount() -> Int { imported }
}

private actor FakePaletteShareConsumer: PaletteShareImportConsuming {
    func wasImported(tokenHash: String) async throws -> Bool { false }
    func preview(_ request: PaletteShareImportRequest) async throws -> ShareConsumerPreview {
        ShareConsumerPreview(resourceCount: 1)
    }
    func importAtomically(_ request: PaletteShareImportRequest) async throws -> String { "local-palette" }
}

private actor FakeShareEffectRepository: EffectProgramRepositoryServing {
    private var record: EffectProgramRecord

    init(program: EffectProgram) {
        record = EffectProgramRecord(program: program, revision: "revision")
    }

    func list() async throws -> [EffectProgramRecord] { [record] }
    func upsert(_ program: EffectProgram, expectedRevision: String?) async throws -> EffectProgramRecord { record }
    func copy(id: String) async throws -> EffectProgramRecord { record }
    func delete(id: String, expectedRevision: String?) async throws -> [EffectProgramRecord] { [] }
    func exportProgram(id: String) async throws -> Data { Data() }
    func exportAll() async throws -> Data { Data() }
    func previewImport(_ data: Data) async throws -> EffectImportPreview {
        EffectImportPreview(programs: [], errors: [], conflictIDs: [])
    }
    func applyImport(
        _ preview: EffectImportPreview,
        strategy: EffectImportConflictStrategy
    ) async throws -> [EffectProgramRecord] { [record] }
}
