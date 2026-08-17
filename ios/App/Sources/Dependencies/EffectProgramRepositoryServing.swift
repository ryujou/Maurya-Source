import Foundation
import MauryaEffects

protocol EffectProgramRepositoryServing: Sendable {
    func list() async throws -> [EffectProgramRecord]
    func upsert(_ program: EffectProgram, expectedRevision: String?) async throws -> EffectProgramRecord
    func copy(id: String) async throws -> EffectProgramRecord
    func delete(id: String, expectedRevision: String?) async throws -> [EffectProgramRecord]
    func exportProgram(id: String) async throws -> Data
    func exportAll() async throws -> Data
    func previewImport(_ data: Data) async throws -> EffectImportPreview
    func applyImport(_ preview: EffectImportPreview, strategy: EffectImportConflictStrategy) async throws -> [EffectProgramRecord]
}

extension EffectProgramRepository: EffectProgramRepositoryServing {}
