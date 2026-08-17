import Foundation

@MainActor
final class UnavailableShareImportService: ShareImportService {
    let validation = ShareImportValidation.idle
    let section = ShareSection.importShare
    let operation = ShareOperationState.failed("share.service.unavailable")
    let effects: [ShareEffectChoice] = []
    let palettes: [SharePaletteChoice] = []
    func validate(_ input: String) {}
    func show(_ section: ShareSection) {}
    func loadChoices() async {}
    func createEffect(id: String) async {}
    func createPalette(id: UUID) async {}
    func fetchForPreview(_ input: String) async {}
    func confirmImport() async {}
    func cancel() {}
}
