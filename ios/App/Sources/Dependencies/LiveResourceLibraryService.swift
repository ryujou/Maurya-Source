import Foundation
import MauryaResources
import Observation

private actor ResourceLibraryLoader {
    private let repository: CustomPaletteRepository

    init(repository: CustomPaletteRepository) {
        self.repository = repository
    }

    func load() async throws -> ResourceLibrarySnapshot {
        let library = try BuiltinPaletteLibrary.load(verifyAssetHashes: false)
        let custom = try await repository.loadAndRepair()
        var customEntries: [CustomPalettePresentation] = []
        customEntries.reserveCapacity(custom.entries.count)
        for entry in custom.entries {
            customEntries.append(
                CustomPalettePresentation(
                    entry: entry,
                    avatarWebP: try await repository.avatarWebP(id: entry.id)
                )
            )
        }
        return ResourceLibrarySnapshot(
            catalog: library.catalog,
            entries: library.inventory.entries,
            customEntries: customEntries,
            customCount: custom.entries.count,
            customLimit: custom.limit
        )
    }

    func save(
        existingID: UUID?,
        expectedRevision: Int,
        nameZh: String,
        nameJa: String,
        hex: String,
        sourceImageData: Data?,
        cropTransform: AvatarCropTransform
    ) async throws {
        let avatar: Data
        if let sourceImageData {
            avatar = try AvatarImageProcessor.process(sourceImageData, transform: cropTransform)
        } else if let existingID {
            avatar = try await repository.avatarWebP(id: existingID)
        } else {
            throw AvatarImageProcessingError.invalidImage
        }
        guard let color = RGBHex(rawValue: hex) else { throw CustomPaletteError.invalidColor }
        _ = try await repository.save(
            existingID: existingID,
            expectedRevision: expectedRevision,
            names: PaletteNames(zh: nameZh, ja: nameJa),
            color: color,
            avatarWebP: avatar
        )
    }

    func delete(id: UUID, expectedRevision: Int) async throws -> DeletedPalette {
        try await repository.delete(id: id, expectedRevision: expectedRevision)
    }

    func restore(_ deletion: DeletedPalette) async throws {
        _ = try await repository.restore(deletion)
    }

    func exportBackup() async throws -> Data { try await repository.exportBackup() }

    func importBackup(_ data: Data, conflictPolicy: BackupConflictPolicy) async throws {
        _ = try await repository.importBackup(data, conflictPolicy: conflictPolicy)
    }
}

@MainActor
@Observable
final class LiveResourceLibraryService: ResourceLibraryService {
    private(set) var snapshot: ResourceLibrarySnapshot?
    private(set) var errorMessage: String?
    private let loader: ResourceLibraryLoader
    private var lastDeletion: DeletedPalette?

    init(repository: CustomPaletteRepository? = nil) {
        let resolved: CustomPaletteRepository
        if let repository {
            resolved = repository
        } else {
            let root = URL.applicationSupportDirectory.appending(path: "Maurya/Palettes", directoryHint: .isDirectory)
            resolved = CustomPaletteRepository(storage: FileCustomPaletteStorage(rootURL: root))
        }
        loader = ResourceLibraryLoader(repository: resolved)
    }

    func load() async {
        do {
            snapshot = try await loader.load()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveCustom(
        existingID: UUID?,
        expectedRevision: Int,
        nameZh: String,
        nameJa: String,
        hex: String,
        sourceImageData: Data?,
        cropTransform: AvatarCropTransform
    ) async -> Bool {
        await performMutation {
            try await loader.save(
                existingID: existingID,
                expectedRevision: expectedRevision,
                nameZh: nameZh,
                nameJa: nameJa,
                hex: hex,
                sourceImageData: sourceImageData,
                cropTransform: cropTransform
            )
        }
    }

    func deleteCustom(id: UUID, expectedRevision: Int) async -> Bool {
        await performMutation { lastDeletion = try await loader.delete(id: id, expectedRevision: expectedRevision) }
    }

    func undoDelete() async -> Bool {
        guard let deletion = lastDeletion else { return false }
        return await performMutation {
            try await loader.restore(deletion)
            lastDeletion = nil
        }
    }

    func exportBackup() async throws -> Data { try await loader.exportBackup() }

    func importBackup(_ data: Data, conflictPolicy: BackupConflictPolicy) async -> Bool {
        await performMutation { try await loader.importBackup(data, conflictPolicy: conflictPolicy) }
    }

    private func performMutation(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            snapshot = try await loader.load()
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }
}

@MainActor
@Observable
final class FakeResourceLibraryService: ResourceLibraryService {
    var snapshot: ResourceLibrarySnapshot?
    var errorMessage: String?

    init(
        snapshot: ResourceLibrarySnapshot? = .init(
            catalog: PaletteCatalog(franchises: [], groups: [], characters: []),
            entries: [], customEntries: [], customCount: 0, customLimit: 50
        ),
        errorMessage: String? = nil
    ) {
        self.snapshot = snapshot
        self.errorMessage = errorMessage
    }

    func load() async {}
    func saveCustom(
        existingID: UUID?, expectedRevision: Int, nameZh: String, nameJa: String, hex: String, sourceImageData: Data?,
        cropTransform: AvatarCropTransform
    ) async -> Bool { true }
    func deleteCustom(id: UUID, expectedRevision: Int) async -> Bool { true }
    func undoDelete() async -> Bool { true }
    func exportBackup() async throws -> Data { Data() }
    func importBackup(_ data: Data, conflictPolicy: BackupConflictPolicy) async -> Bool { true }
}
