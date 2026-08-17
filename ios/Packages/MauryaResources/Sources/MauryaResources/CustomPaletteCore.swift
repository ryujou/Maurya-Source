import CryptoKit
import Foundation
import MauryaShare

public struct PaletteNames: Codable, Sendable, Equatable {
    public let zh: String
    public let ja: String

    public init(zh: String, ja: String) throws {
        func normalize(_ value: String) throws -> String {
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard result.unicodeScalars.count <= 32,
                result.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f })
            else {
                throw CustomPaletteError.invalidName
            }
            return result
        }
        self.zh = try normalize(zh)
        self.ja = try normalize(ja)
        guard self.zh.isEmpty == false || self.ja.isEmpty == false else {
            throw CustomPaletteError.invalidName
        }
    }

    public func displayName(locale: PaletteLocale) -> String {
        switch locale {
        case .simplifiedChinese: zh.isEmpty ? ja : zh
        case .japanese: ja.isEmpty ? zh : ja
        }
    }
}

public struct CustomPaletteEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let names: PaletteNames
    public let color: RGBHex
    public let revision: Int
    public let avatarFilename: String
    public let avatar: AvatarMetadata
    public let createdAt: String
    public let updatedAt: String
}

public struct CustomPaletteSnapshot: Sendable, Equatable {
    public let entries: [CustomPaletteEntry]
    public let usedBytes: Int
    public let limit: Int
}

public struct DeletedPalette: Sendable, Equatable {
    public let entry: CustomPaletteEntry
    public let avatarWebP: Data
}

public enum CustomPaletteError: Error, Sendable, Equatable {
    case invalidName
    case invalidColor
    case invalidIdentifier
    case invalidBackup
    case backupSizeExceeded
    case capacityReached(limit: Int)
    case notFound
    case revisionConflict
    case duplicateContent(existingID: UUID)
    case corruptIndex
}

public enum BackupConflictPolicy: Sendable {
    case skip
    case overwrite
}

public struct BackupImportResult: Sendable, Equatable {
    public let imported: Int
    public let skipped: Int
}

public enum CustomPaletteBackupCodec {
    public static let schemaVersion = 1
    public static let maximumBytes = 1_024 * 1_024

    public struct Item: Codable, Sendable, Equatable {
        public let id: String
        public let nameZh: String
        public let nameJa: String
        public let hex: String
        public let createdAt: String
        public let updatedAt: String
        public let avatarWebpBase64: String
        public let avatarSha256: String
    }

    public struct Document: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let exportedAt: String
        public let entries: [Item]
    }

    public struct ValidatedItem: Sendable, Equatable {
        public let id: UUID
        public let names: PaletteNames
        public let color: RGBHex
        public let createdAt: String
        public let updatedAt: String
        public let avatarWebP: Data
        public let avatar: AvatarMetadata
    }

    public static func encode(
        entries: [(CustomPaletteEntry, Data)],
        exportedAt: String
    ) throws -> Data {
        let items = try entries.map { entry, avatar in
            let metadata = try AvatarValidator.validate(avatar, expectedSHA256: entry.avatar.sha256)
            return Item(
                id: entry.id.uuidString.lowercased(),
                nameZh: entry.names.zh,
                nameJa: entry.names.ja,
                hex: entry.color.rawValue,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                avatarWebpBase64: avatar.base64EncodedString(),
                avatarSha256: metadata.sha256
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let result = try encoder.encode(Document(schemaVersion: schemaVersion, exportedAt: exportedAt, entries: items))
        guard result.count <= maximumBytes else { throw CustomPaletteError.backupSizeExceeded }
        return result
    }

    public static func decode(_ data: Data) throws -> [ValidatedItem] {
        guard data.count <= maximumBytes else { throw CustomPaletteError.backupSizeExceeded }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) } catch { throw CustomPaletteError.invalidBackup }
        guard document.schemaVersion == schemaVersion,
            document.entries.count <= CustomPaletteRepository.maximumEntries
        else {
            throw CustomPaletteError.invalidBackup
        }
        var IDs: Set<UUID> = []
        return try document.entries.map { item in
            guard let id = UUID(uuidString: item.id),
                id.uuidString.lowercased() == item.id,
                IDs.insert(id).inserted,
                let color = RGBHex(rawValue: item.hex),
                let avatar = Data(base64Encoded: item.avatarWebpBase64),
                avatar.base64EncodedString() == item.avatarWebpBase64
            else {
                throw CustomPaletteError.invalidBackup
            }
            let metadata = try AvatarValidator.validate(avatar, expectedSHA256: item.avatarSha256)
            return try ValidatedItem(
                id: id,
                names: PaletteNames(zh: item.nameZh, ja: item.nameJa),
                color: color,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                avatarWebP: avatar,
                avatar: metadata
            )
        }
    }
}

public extension CustomPaletteEntry {
    func makeShareEnvelope(avatarWebP: Data) throws -> ShareEnvelope {
        _ = try AvatarValidator.validate(avatarWebP, expectedSHA256: avatar.sha256)
        return try ShareEnvelopeCodec.makePalette(
            names: ShareDisplayName(zh: names.zh, ja: names.ja),
            hex: color.rawValue,
            avatarWebP: avatarWebP
        )
    }
}
