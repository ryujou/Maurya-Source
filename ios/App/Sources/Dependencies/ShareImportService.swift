import Foundation
import MauryaShare

struct ValidatedShareLink: Equatable, Sendable {
    let token: String
    let canonicalURL: URL
}

enum ShareImportValidation: Equatable, Sendable {
    case idle
    case valid(ValidatedShareLink)
    case invalid
}

enum ShareSection: Equatable, Sendable {
    case create
    case importShare
}

struct ShareEffectChoice: Identifiable, Equatable, Sendable {
    let id: String
    let names: ShareDisplayName
    let sourceKind: String
}

struct SharePaletteChoice: Identifiable, Equatable, Sendable {
    let id: UUID
    let names: ShareDisplayName
    let hex: String
}

struct ShareFixturePreview: Sendable, Equatable {
    let name: String
    let kindKey: String
    let source: String
}

enum ShareOperationState: Sendable, Equatable {
    case idle
    case busy
    case created(CreatedShare, ShareQRCodeDescriptor)
    case preview(ShareImportPreview)
    case fixturePreview(ShareFixturePreview)
    case imported(CompletedShareImport)
    case failed(String)
}

@MainActor
protocol ShareImportService: AnyObject {
    var validation: ShareImportValidation { get }
    var section: ShareSection { get }
    var operation: ShareOperationState { get }
    var effects: [ShareEffectChoice] { get }
    var palettes: [SharePaletteChoice] { get }
    func validate(_ input: String)
    func show(_ section: ShareSection)
    func loadChoices() async
    func createEffect(id: String) async
    func createPalette(id: UUID) async
    func fetchForPreview(_ input: String) async
    func confirmImport() async
    func cancel()
}
