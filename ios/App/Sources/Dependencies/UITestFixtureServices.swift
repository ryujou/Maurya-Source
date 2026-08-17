import Foundation
import MauryaEffects
import MauryaResources
import MauryaShare
import Observation

@MainActor
@Observable
final class UITestEffectProgramService: EffectProgramService {
    static let programID = "ui-fixture-script"
    static let initialScript = ##"effect "UI Fixture" { all.color("#FF8800"); wait(500ms); }"##
    static let recoveredScript = ##"effect "Recovered Fixture" { all.color("#39C5BB"); wait(750ms); }"##

    private(set) var records: [EffectProgramRecord]
    private(set) var selectedID: String? = programID
    private(set) var errorMessage: String?
    private(set) var importPreview: EffectImportPreview?
    private(set) var lastSavedDocument: String?

    init() {
        let program = EffectProgram(
            id: Self.programID,
            nameZh: "UI Fixture Effect",
            nameJa: "UI Fixture Effect",
            createdAt: 1_700_000_000_000,
            updatedAt: 1_700_000_000_000,
            sourceKind: .script,
            scriptSource: Self.initialScript
        )
        records = [EffectProgramRecord(program: program, revision: "fixture-1")]
    }

    func load() async {}

    func select(id: String) {
        selectedID = records.contains { $0.program.id == id } ? id : nil
    }

    func selectedRecord() -> EffectProgramRecord? {
        records.first { $0.program.id == selectedID }
    }

    func create(kind: MauryaEffects.EffectSourceKind, nameZh: String, nameJa: String) async {}
    func copySelected() async {}
    func copySelectedAsScript() async {}
    func renameSelected(nameZh: String, nameJa: String) async {}
    func deleteSelected() async {}

    func save(document: String) async throws -> CompiledEffect {
        await Task.yield()
        guard let index = records.firstIndex(where: { $0.program.id == selectedID }) else {
            throw EffectProgramError.programNotFound(Self.programID)
        }
        let old = records[index].program
        let updated = EffectProgram(
            id: old.id,
            nameZh: old.nameZh,
            nameJa: old.nameJa,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt + 1,
            sourceKind: old.sourceKind,
            scriptSource: document
        )
        let compiled = try EffectProgramCompiler.compile(updated)
        lastSavedDocument = document
        errorMessage = nil
        return compiled
    }

    func compileSelected() throws -> CompiledEffect {
        guard let program = selectedRecord()?.program else {
            throw EffectProgramError.programNotFound(Self.programID)
        }
        return try EffectProgramCompiler.compile(program)
    }

    func exportSelected() async throws -> Data { Data("{}".utf8) }
    func exportAll() async throws -> Data { Data("{}".utf8) }
    func previewImport(_ data: Data) async {}
    func applyImport(strategy: EffectImportConflictStrategy) async {}
}

@MainActor
@Observable
final class UITestResourceLibraryService: ResourceLibraryService {
    private(set) var snapshot: ResourceLibrarySnapshot?
    private(set) var errorMessage: String?

    init() {
        do {
            let library = try BuiltinPaletteLibrary.load()
            snapshot = ResourceLibrarySnapshot(
                catalog: library.catalog,
                entries: library.inventory.entries,
                customEntries: [],
                customCount: 0,
                customLimit: 50
            )
        } catch {
            snapshot = nil
            errorMessage = "ui.fixture.resources.load-failed"
        }
    }

    func load() async {}
    func saveCustom(
        existingID: UUID?, expectedRevision: Int, nameZh: String, nameJa: String, hex: String, sourceImageData: Data?,
        cropTransform: AvatarCropTransform
    ) async -> Bool { true }
    func deleteCustom(id: UUID, expectedRevision: Int) async -> Bool { true }
    func undoDelete() async -> Bool { true }
    func exportBackup() async throws -> Data { Data("{}".utf8) }
    func importBackup(_ data: Data, conflictPolicy: BackupConflictPolicy) async -> Bool { true }
}

@MainActor
@Observable
final class UITestShareImportService: ShareImportService {
    private(set) var validation = ShareImportValidation.idle
    private(set) var section = ShareSection.importShare
    private(set) var operation: ShareOperationState
    let effects: [ShareEffectChoice] = []
    let palettes: [SharePaletteChoice] = []
    private var generation = 0

    init(arguments: [String]) {
        if arguments.contains("-maurya-ui-share-preview") {
            operation = .fixturePreview(
                ShareFixturePreview(
                    name: "UI Fixture Effect",
                    kindKey: "share.kind.script",
                    source: UITestEffectProgramService.recoveredScript
                ))
        } else if arguments.contains("-maurya-ui-share-error") {
            operation = .failed("ui.fixture.share.error")
        } else {
            operation = .idle
        }
    }

    func validate(_ input: String) {
        validation = input.isEmpty ? .invalid : .idle
    }

    func show(_ section: ShareSection) {
        self.section = section
        operation = .idle
    }

    func loadChoices() async {}
    func createEffect(id: String) async {}
    func createPalette(id: UUID) async {}

    func fetchForPreview(_ input: String) async {
        generation &+= 1
        let current = generation
        operation = .busy
        do {
            try await Task.sleep(for: .seconds(30))
            guard generation == current else { return }
            operation = .failed("ui.fixture.share.error")
        } catch is CancellationError {
            guard generation == current else { return }
            operation = .idle
        } catch {
            guard generation == current else { return }
            operation = .failed("ui.fixture.share.error")
        }
    }

    func confirmImport() async {
        operation = .failed("ui.fixture.share.import-disabled")
    }

    func cancel() {
        generation &+= 1
        operation = .idle
    }
}

@MainActor
enum UITestFixturePreparation {
    static func prepareEditorRecovery() -> Bool {
        let url = URL.applicationSupportDirectory
            .appending(path: "Maurya/Editor", directoryHint: .isDirectory)
            .appending(path: "\(UITestEffectProgramService.programID).autosave.json")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(UITestEffectProgramService.recoveredScript.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
