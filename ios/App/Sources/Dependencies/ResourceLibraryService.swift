import Foundation
import MauryaResources

struct CustomPalettePresentation: Identifiable, Sendable, Equatable {
    let entry: CustomPaletteEntry
    let avatarWebP: Data
    var id: UUID { entry.id }
}

struct ResourceLibrarySnapshot: Sendable, Equatable {
    let catalog: PaletteCatalog
    let entries: [ResourceInventoryEntry]
    let customEntries: [CustomPalettePresentation]
    let customCount: Int
    let customLimit: Int
}

@MainActor
protocol ResourceLibraryService: AnyObject {
    var snapshot: ResourceLibrarySnapshot? { get }
    var errorMessage: String? { get }
    func load() async
    @discardableResult func saveCustom(
        existingID: UUID?,
        expectedRevision: Int,
        nameZh: String,
        nameJa: String,
        hex: String,
        sourceImageData: Data?,
        cropTransform: AvatarCropTransform
    ) async -> Bool
    @discardableResult func deleteCustom(id: UUID, expectedRevision: Int) async -> Bool
    @discardableResult func undoDelete() async -> Bool
    func exportBackup() async throws -> Data
    @discardableResult func importBackup(_ data: Data, conflictPolicy: BackupConflictPolicy) async -> Bool
}
