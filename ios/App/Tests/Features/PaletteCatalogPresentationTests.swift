import MauryaResources
import Testing
import UIKit

@testable import Maurya

struct PaletteCatalogPresentationTests {
    @Test func bangDreamHierarchyExposesAfterglowCharactersInsteadOfFlatteningTheCatalog() throws {
        let library = try BuiltinPaletteLibrary.load(verifyAssetHashes: false)
        let hierarchy = PaletteHierarchy(catalog: library.catalog)

        let afterglow = try #require(
            hierarchy.groupsByFranchise["bangdream"]?.first { $0.id == "bangdream_afterglow" }
        )
        let characters = try #require(hierarchy.charactersByGroup[afterglow.id])

        #expect(afterglow.memberIds.count == 5)
        #expect(characters.count == 5)
        #expect(characters.contains { $0.nameZh == "美竹兰" && $0.nameJa == "美竹蘭" })
    }

    @Test func characterAndGroupImagesArePackagedAndDecodableOnIOS() throws {
        let library = try BuiltinPaletteLibrary.load(verifyAssetHashes: false)
        let inventory = Dictionary(uniqueKeysWithValues: library.inventory.entries.map { ($0.id, $0) })

        for id in ["bangdream_afterglow", "bangdream_char_006"] {
            let entry = try #require(inventory[id])
            let url = try BuiltinPaletteLibrary.resourceURL(for: entry)
            let image = try #require(UIImage(contentsOfFile: url.path))

            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }
}
