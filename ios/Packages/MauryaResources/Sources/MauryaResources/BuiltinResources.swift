import CryptoKit
import Foundation

public enum ResourceKind: String, Codable, Sendable {
    case group
    case character
}

public enum LicenseStatus: String, Codable, Sendable {
    case reviewRequired
    case approved
    case rejected
}

public struct ResourceInventoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ResourceKind
    public let nameZh: String
    public let nameJa: String
    public let affiliation: String
    public let hex: String
    public let path: String
    public let sha256: String
    public let sourceURL: String
    public let imageSourceURL: String
    public let licenseStatus: LicenseStatus
    public let licenseNote: String
}

public struct ResourceInventory: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let catalogSHA256: String
    public let entries: [ResourceInventoryEntry]
}

public enum BuiltinResourceError: Error, Sendable, Equatable {
    case missingResource(String)
    case invalidCatalog
    case invalidInventory
    case duplicateID(String)
    case inventoryMismatch(String)
    case hashMismatch(String)
}

public struct BuiltinPaletteLibrary: Sendable {
    public let catalog: PaletteCatalog
    public let inventory: ResourceInventory

    public static func load(verifyAssetHashes: Bool = true) throws -> Self {
        guard let catalogURL = Bundle.module.url(forResource: "palette_catalog", withExtension: "json"),
            let inventoryURL = Bundle.module.url(forResource: "asset_inventory", withExtension: "json")
        else {
            throw BuiltinResourceError.missingResource("catalog or inventory")
        }
        let catalogData = try Data(contentsOf: catalogURL)
        let inventoryData = try Data(contentsOf: inventoryURL)
        let decoder = JSONDecoder()
        guard let catalog = try? decoder.decode(PaletteCatalog.self, from: catalogData) else {
            throw BuiltinResourceError.invalidCatalog
        }
        guard let inventory = try? decoder.decode(ResourceInventory.self, from: inventoryData),
            inventory.schemaVersion == 1
        else {
            throw BuiltinResourceError.invalidInventory
        }
        let library = Self(catalog: catalog, inventory: inventory)
        try library.validate(catalogData: catalogData, verifyAssetHashes: verifyAssetHashes)
        return library
    }

    public func data(for entry: ResourceInventoryEntry) throws -> Data {
        try Data(contentsOf: Self.resourceURL(for: entry))
    }

    /// Returns the packaged image URL so UI clients decode only visible rows.
    public static func resourceURL(for entry: ResourceInventoryEntry) throws -> URL {
        let path = entry.path as NSString
        let filename = path.lastPathComponent as NSString
        guard
            let url = Bundle.module.url(
                forResource: filename.deletingPathExtension,
                withExtension: filename.pathExtension
            )
        else {
            throw BuiltinResourceError.missingResource(entry.path)
        }
        return url
    }

    private func validate(catalogData: Data, verifyAssetHashes: Bool) throws {
        guard Self.sha256(catalogData) == inventory.catalogSHA256 else {
            throw BuiltinResourceError.hashMismatch("palette_catalog.json")
        }
        let catalogIDs = catalog.groups.map(\.id) + catalog.characters.map(\.id)
        if let duplicate = Self.firstDuplicate(catalogIDs) { throw BuiltinResourceError.duplicateID(duplicate) }
        let inventoryIDs = inventory.entries.map(\.id)
        if let duplicate = Self.firstDuplicate(inventoryIDs) { throw BuiltinResourceError.duplicateID(duplicate) }
        guard Set(catalogIDs) == Set(inventoryIDs), catalogIDs.count == inventory.entries.count else {
            throw BuiltinResourceError.inventoryMismatch("catalog and inventory IDs differ")
        }
        for entry in inventory.entries {
            guard RGBHex(rawValue: entry.hex) != nil else {
                throw BuiltinResourceError.inventoryMismatch("invalid color for \(entry.id)")
            }
            if verifyAssetHashes {
                let bytes = try data(for: entry)
                guard Self.sha256(bytes) == entry.sha256 else {
                    throw BuiltinResourceError.hashMismatch(entry.path)
                }
            }
        }
    }

    private static func firstDuplicate(_ values: [String]) -> String? {
        var seen: Set<String> = []
        return values.first { seen.insert($0).inserted == false }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
