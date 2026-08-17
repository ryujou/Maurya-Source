import Foundation
import MauryaResources
import Testing

struct BuiltinResourcesTests {
    @Test(.timeLimit(.minutes(1))) func inventoryExactlyMatchesAndroidCatalogAndHashes() throws {
        let library = try BuiltinPaletteLibrary.load()
        #expect(library.catalog.franchises.count == 4)
        #expect(library.catalog.groups.count == 55)
        #expect(library.catalog.characters.count == 505)
        #expect(library.inventory.entries.count == 560)
        #expect(library.inventory.entries.allSatisfy { $0.licenseStatus == .reviewRequired })
    }

    @Test func hierarchyHidesAndroidAttributeAndUnitGroups() throws {
        let library = try BuiltinPaletteLibrary.load(verifyAssetHashes: false)
        let hierarchy = PaletteHierarchy(catalog: library.catalog)
        let visible = hierarchy.groupsByFranchise.values.flatMap { $0 }
        #expect(visible.allSatisfy { $0.groupType != "attribute" && $0.groupType != "unit" })
        #expect(hierarchy.charactersByGroup.values.flatMap { $0 }.count == 505)
    }

    @Test func everyInventoryEntryExposesItsPackagedAvatarURL() throws {
        let library = try BuiltinPaletteLibrary.load(verifyAssetHashes: false)
        for entry in library.inventory.entries {
            let url = try BuiltinPaletteLibrary.resourceURL(for: entry)
            #expect(url.isFileURL)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try Data(contentsOf: url).isEmpty == false)
        }
    }
}
