import Foundation
import MauryaEffects
import Observation

@MainActor
@Observable
final class UnavailableEffectProgramService: EffectProgramService {
    private(set) var records: [EffectProgramRecord] = []
    private(set) var selectedID: String?
    private(set) var errorMessage: String?
    private(set) var importPreview: EffectImportPreview?

    init(
        error: any Error,
        language: EffectPresentationLanguage = .english
    ) {
        errorMessage = EffectErrorPresenter.message(for: error, language: language)
    }

    func load() async {}
    func select(id: String) {}
    func selectedRecord() -> EffectProgramRecord? { nil }
    func create(kind: EffectSourceKind, nameZh: String, nameJa: String) async {}
    func copySelected() async {}
    func copySelectedAsScript() async {}
    func renameSelected(nameZh: String, nameJa: String) async {}
    func deleteSelected() async {}
    func save(document: String) async throws -> CompiledEffect {
        throw EffectProgramError.storageCorrupt
    }
    func compileSelected() throws -> CompiledEffect {
        throw EffectProgramError.storageCorrupt
    }
    func exportSelected() async throws -> Data {
        throw EffectProgramError.storageCorrupt
    }
    func exportAll() async throws -> Data { throw EffectProgramError.storageCorrupt }
    func previewImport(_ data: Data) async {}
    func applyImport(strategy: EffectImportConflictStrategy) async {}
}
