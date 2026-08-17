import Foundation

public enum ShareKind: String, Sendable, Codable, CaseIterable {
    case effect
    case palette
}

public struct ShareDisplayName: Sendable, Equatable {
    public let zh: String
    public let ja: String

    public init(zh: String, ja: String) {
        self.zh = zh
        self.ja = ja
    }
}

public enum EffectSourceKind: String, Sendable, Codable {
    case blocks
    case script
}

public struct EffectSharePayload: Sendable, Equatable {
    public let sourceKind: EffectSourceKind
    public let editorSchema: Int
    public let programSchema: Int
    public let source: String

    public init(sourceKind: EffectSourceKind, editorSchema: Int, programSchema: Int, source: String) {
        self.sourceKind = sourceKind
        self.editorSchema = editorSchema
        self.programSchema = programSchema
        self.source = source
    }
}

public struct PaletteSharePayload: Sendable, Equatable {
    public let hex: String
    public let avatarWebP: Data
    public let avatarSHA256: String

    public init(hex: String, avatarWebP: Data, avatarSHA256: String) {
        self.hex = hex
        self.avatarWebP = avatarWebP
        self.avatarSHA256 = avatarSHA256
    }
}

public enum SharePayload: Sendable, Equatable {
    case effect(EffectSharePayload)
    case palette(PaletteSharePayload)

    public var kind: ShareKind {
        switch self {
        case .effect: .effect
        case .palette: .palette
        }
    }
}

public struct ShareEnvelope: Sendable, Equatable {
    public let schema: Int
    public let kind: ShareKind
    public let displayName: ShareDisplayName
    public let payload: SharePayload
    public let contentHash: String
    public let createdAt: Date?

    public init(
        schema: Int = 1,
        kind: ShareKind,
        displayName: ShareDisplayName,
        payload: SharePayload,
        contentHash: String,
        createdAt: Date? = nil
    ) {
        self.schema = schema
        self.kind = kind
        self.displayName = displayName
        self.payload = payload
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}

public enum ShareValidationError: Error, Sendable, Equatable {
    case invalidToken
    case invalidJSON
    case duplicateJSONKey
    case JSONDepthExceeded
    case JSONLimitExceeded
    case unknownOrMissingField
    case unsupportedSchema
    case kindMismatch
    case invalidDisplayName
    case invalidPayload
    case invalidHash
    case compressedSizeExceeded
    case uncompressedSizeExceeded
    case invalidGzip
    case invalidUTF8
    case invalidDate
}
