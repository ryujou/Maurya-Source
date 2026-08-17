import Foundation
import MauryaEffects
import Observation

@MainActor
@Observable
final class LiveEffectProgramService: EffectProgramService {
    private(set) var records: [EffectProgramRecord] = []
    private(set) var selectedID: String?
    private(set) var errorMessage: String?
    private(set) var importPreview: EffectImportPreview?

    private let repository: any EffectProgramRepositoryServing
    private let now: @Sendable () -> Int64
    private let language: @MainActor @Sendable () -> EffectPresentationLanguage

    init(
        repository: (any EffectProgramRepositoryServing)? = nil,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
        language: @escaping @MainActor @Sendable () -> EffectPresentationLanguage = { .english }
    ) throws {
        self.now = now
        self.language = language
        if let repository {
            self.repository = repository
        } else {
            let directory = URL.applicationSupportDirectory.appending(path: "Maurya/Effects", directoryHint: .isDirectory)
            self.repository = try EffectProgramRepository(storage: FileEffectProgramStorage(directoryURL: directory))
        }
    }

    func load() async {
        do {
            records = try await repository.list()
            reconcileSelection()
            errorMessage = nil
        } catch {
            errorMessage = EffectErrorPresenter.message(for: error, language: language())
        }
    }

    func select(id: String) {
        selectedID = records.contains { $0.program.id == id } ? id : nil
    }

    func selectedRecord() -> EffectProgramRecord? {
        records.first { $0.program.id == selectedID }
    }

    func create(kind: EffectSourceKind, nameZh: String, nameJa: String) async {
        let timestamp = now()
        let names = Self.names(nameZh: nameZh, nameJa: nameJa, kind: kind)
        let program = EffectProgram(
            id: UUID().uuidString,
            nameZh: names.zh,
            nameJa: names.ja,
            workspaceJSON: kind == .blocks ? Self.emptyWorkspace : "",
            createdAt: timestamp,
            updatedAt: timestamp,
            sourceKind: kind,
            scriptSource: kind == .script ? Self.emptyScript : ""
        )
        do {
            let record = try await repository.upsert(program, expectedRevision: nil)
            records.append(record)
            selectedID = record.program.id
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    func copySelected() async {
        guard let selectedID else { return }
        do {
            let record = try await repository.copy(id: selectedID)
            records.append(record)
            self.selectedID = record.program.id
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    func copySelectedAsScript() async {
        guard let source = selectedRecord()?.program, source.sourceKind == .blocks else { return }
        do {
            let compiled = try EffectProgramCompiler.compile(source)
            let timestamp = now()
            let script = EffectScriptFormatter.fromCompiled(source.nameZh, compiled)
            let program = EffectProgram(
                id: UUID().uuidString,
                nameZh: "\(source.nameZh) 代码版",
                nameJa: "\(source.nameJa) コード版",
                createdAt: timestamp,
                updatedAt: timestamp,
                sourceKind: .script,
                scriptSource: script
            )
            let record = try await repository.upsert(program, expectedRevision: nil)
            records.append(record)
            selectedID = record.program.id
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    func renameSelected(nameZh: String, nameJa: String) async {
        guard let record = selectedRecord() else { return }
        let names = Self.names(nameZh: nameZh, nameJa: nameJa, kind: record.program.sourceKind)
        let old = record.program
        let renamed = EffectProgram(
            id: old.id, nameZh: names.zh, nameJa: names.ja,
            workspaceJSON: old.workspaceJSON, astJSON: old.astJSON, astSHA256: old.astSHA256,
            blockCount: old.blockCount, estimatedDurationMilliseconds: old.estimatedDurationMilliseconds,
            createdAt: old.createdAt, updatedAt: now(), editorSchema: old.editorSchema,
            programSchema: old.programSchema, sourceKind: old.sourceKind, scriptSource: old.scriptSource
        )
        do {
            let saved = try await repository.upsert(renamed, expectedRevision: record.revision)
            if let index = records.firstIndex(where: { $0.program.id == saved.program.id }) {
                records[index] = saved
            }
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    func deleteSelected() async {
        guard let record = selectedRecord() else { return }
        do {
            records = try await repository.delete(id: record.program.id, expectedRevision: record.revision)
            reconcileSelection()
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    func save(document: String) async throws -> CompiledEffect {
        guard let record = selectedRecord() else { throw EffectProgramError.programNotFound("") }
        let old = record.program
        let updated = EffectProgram(
            id: old.id, nameZh: old.nameZh, nameJa: old.nameJa,
            workspaceJSON: old.sourceKind == .blocks ? document : old.workspaceJSON,
            astJSON: old.astJSON, astSHA256: old.astSHA256, blockCount: old.blockCount,
            estimatedDurationMilliseconds: old.estimatedDurationMilliseconds,
            createdAt: old.createdAt, updatedAt: now(), editorSchema: old.editorSchema,
            programSchema: old.programSchema, sourceKind: old.sourceKind,
            scriptSource: old.sourceKind == .script ? document : old.scriptSource
        )
        let compiled = try EffectProgramCompiler.compile(updated)
        let saved = try await repository.upsert(updated, expectedRevision: record.revision)
        if let index = records.firstIndex(where: { $0.program.id == saved.program.id }) { records[index] = saved }
        errorMessage = nil
        return compiled
    }

    func compileSelected() throws -> CompiledEffect {
        guard let program = selectedRecord()?.program else { throw EffectProgramError.programNotFound("") }
        return try EffectProgramCompiler.compile(program)
    }

    func exportSelected() async throws -> Data {
        guard let selectedID else { throw EffectProgramError.programNotFound("") }
        return try await repository.exportProgram(id: selectedID)
    }

    func exportAll() async throws -> Data { try await repository.exportAll() }

    func previewImport(_ data: Data) async {
        do {
            importPreview = try await repository.previewImport(data)
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    func applyImport(strategy: EffectImportConflictStrategy) async {
        guard let importPreview else { return }
        do {
            records = try await repository.applyImport(importPreview, strategy: strategy)
            self.importPreview = nil
            reconcileSelection()
            errorMessage = nil
        } catch { errorMessage = EffectErrorPresenter.message(for: error, language: language()) }
    }

    private func reconcileSelection() {
        if let selectedID, records.contains(where: { $0.program.id == selectedID }) { return }
        selectedID = records.first?.program.id
    }

    private static func names(
        nameZh: String,
        nameJa: String,
        kind: EffectSourceKind
    ) -> (zh: String, ja: String) {
        let zh = String(nameZh.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        let ja = String(nameJa.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        if zh.isEmpty == false || ja.isEmpty == false {
            return (zh.isEmpty ? ja : zh, ja.isEmpty ? zh : ja)
        }
        return kind == .blocks
            ? ("新建积木灯效", "新規ブロックエフェクト")
            : ("新建脚本灯效", "新規スクリプトエフェクト")
    }

    private static let emptyWorkspace =
        #"{"blocks":{"languageVersion":0,"blocks":[{"type":"maurya_start","id":"start","x":40,"y":40,"next":{"block":{"type":"maurya_wait","id":"start-wait","fields":{"DURATION":500,"UNIT":"MS"}}}}]}}"#
    private static let emptyScript = ##"effect "New" { all.color("#FF8800"); wait(500ms); }"##
}
