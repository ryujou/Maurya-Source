import Foundation

public enum PaletteLocale: Sendable {
    case simplifiedChinese
    case japanese
}

public struct PaletteCatalog: Codable, Sendable, Equatable {
    public let franchises: [PaletteFranchise]
    public let groups: [PaletteGroup]
    public let characters: [PaletteCharacter]

    public init(
        franchises: [PaletteFranchise],
        groups: [PaletteGroup],
        characters: [PaletteCharacter]
    ) {
        self.franchises = franchises
        self.groups = groups
        self.characters = characters
    }
}

public struct PaletteFranchise: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let labelZh: String?
    public let labelJa: String?
    public let sortOrder: Int

    public func displayLabel(locale: PaletteLocale) -> String {
        switch locale {
        case .simplifiedChinese: labelZh?.nilIfBlank ?? label
        case .japanese: labelJa?.nilIfBlank ?? label
        }
    }
}

public struct PaletteGroup: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let franchiseId: String
    public let seriesLabelZh: String
    public let seriesLabelJa: String
    public let nameZh: String
    public let nameJa: String
    public let sourceName: String
    public let hex: String
    public let image: String
    public let memberIds: [String]
    public let sourceUrl: String
    public let imageSourceUrl: String
    public let groupType: String
    public let imageKind: String
    public let sortOrder: Int

    public func displayName(locale: PaletteLocale) -> String {
        locale == .japanese ? nameJa : nameZh
    }
}

public struct PaletteCharacter: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let franchiseId: String
    public let groupId: String
    public let nameZh: String
    public let nameJa: String
    public let hex: String
    public let image: String
    public let sourceUrl: String
    public let imageSourceUrl: String
    public let sortOrder: Int

    public func displayName(locale: PaletteLocale) -> String {
        locale == .japanese ? nameJa : nameZh
    }
}

public struct PaletteHierarchy: Sendable, Equatable {
    public let franchises: [PaletteFranchise]
    public let groupsByFranchise: [String: [PaletteGroup]]
    public let charactersByGroup: [String: [PaletteCharacter]]

    public init(catalog: PaletteCatalog) {
        franchises = catalog.franchises.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
        groupsByFranchise = Dictionary(
            grouping: catalog.groups.filter { !Self.hiddenGroupTypes.contains($0.groupType) },
            by: \.franchiseId
        ).mapValues { $0.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) } }
        charactersByGroup = Dictionary(grouping: catalog.characters, by: \.groupId)
            .mapValues { $0.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) } }
    }

    private static let hiddenGroupTypes: Set<String> = ["attribute", "unit"]
}

public struct RGBHex: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 7, normalized.first == "#",
            normalized.dropFirst().allSatisfy(\.isHexDigit)
        else { return nil }
        self.rawValue = normalized
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
