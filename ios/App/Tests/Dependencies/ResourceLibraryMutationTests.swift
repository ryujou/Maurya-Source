import Foundation
import MauryaResources
import Testing

@testable import Maurya

@MainActor
struct ResourceLibraryMutationTests {
    @Test func failedImportPreservesCachedLibraryAndReportsFailure() async {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "maurya-resource-mutation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CustomPaletteRepository(
            storage: FileCustomPaletteStorage(rootURL: directory)
        )
        let service = LiveResourceLibraryService(repository: repository)
        await service.load()
        let initial = service.snapshot

        let imported = await service.importBackup(Data("not-json".utf8), conflictPolicy: .overwrite)

        #expect(imported == false)
        #expect(service.snapshot == initial)
        #expect(service.errorMessage != nil)
    }
}
