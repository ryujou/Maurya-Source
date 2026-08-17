import Foundation
import MauryaEffects

@MainActor
protocol EffectProgramService: AnyObject {
    var records: [EffectProgramRecord] { get }
    var selectedID: String? { get }
    var errorMessage: String? { get }
    var importPreview: EffectImportPreview? { get }

    func load() async
    func select(id: String)
    func selectedRecord() -> EffectProgramRecord?
    func create(kind: EffectSourceKind, nameZh: String, nameJa: String) async
    func copySelected() async
    func copySelectedAsScript() async
    func renameSelected(nameZh: String, nameJa: String) async
    func deleteSelected() async
    func save(document: String) async throws -> CompiledEffect
    func compileSelected() throws -> CompiledEffect
    func exportSelected() async throws -> Data
    func exportAll() async throws -> Data
    func previewImport(_ data: Data) async
    func applyImport(strategy: EffectImportConflictStrategy) async
}
