import CryptoKit
import Foundation

public enum ShareEnvelopeCodec {
    public static let maximumCompressedBytes = 256 * 1_024
    public static let maximumUncompressedBytes = 2 * 1_024 * 1_024
    public static let maximumSourceBytes = 256 * 1_024
    public static let maximumAvatarBytes = 6_144
    public static let JSONMaximumDepth = 32
    public static let JSONMaximumEntries = 4_096
    public static let editorSchema = 4
    public static let programSchema = 6

    public static func makeEffect(
        names: ShareDisplayName,
        sourceKind: EffectSourceKind,
        source: String
    ) throws -> ShareEnvelope {
        let payload = EffectSharePayload(
            sourceKind: sourceKind,
            editorSchema: editorSchema,
            programSchema: programSchema,
            source: source
        )
        return try build(names: names, payload: .effect(payload))
    }

    public static func makePalette(
        names: ShareDisplayName,
        hex: String,
        avatarWebP: Data
    ) throws -> ShareEnvelope {
        let payload = PaletteSharePayload(
            hex: hex.uppercased(),
            avatarWebP: avatarWebP,
            avatarSHA256: sha256(avatarWebP)
        )
        return try build(names: names, payload: .palette(payload))
    }

    public static func contentHash(
        kind: ShareKind,
        names: ShareDisplayName,
        payload: SharePayload
    ) throws -> String {
        guard kind == payload.kind else { throw ShareValidationError.kindMismatch }
        let canonical = try canonicalPayload(payload)
        var input = Data("maurya-share-v1\0".utf8)
        for component in [kind.rawValue, names.zh, names.ja, canonical] {
            let bytes = Data(component.utf8)
            guard bytes.count <= Int(UInt32.max) else { throw ShareValidationError.JSONLimitExceeded }
            var size = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &size) { input.append(contentsOf: $0) }
            input.append(bytes)
        }
        return sha256(input)
    }

    public static func canonicalEnvelope(
        _ envelope: ShareEnvelope,
        includeCreatedAt: Bool
    ) throws -> Data {
        try validate(envelope, requireCreatedAt: includeCreatedAt)
        var fields = ["\"contentHash\":\(quote(envelope.contentHash))"]
        if includeCreatedAt {
            guard let createdAt = envelope.createdAt else { throw ShareValidationError.invalidDate }
            fields.append("\"createdAt\":\(quote(formatDate(createdAt)))")
        }
        let name = "{\"ja\":\(quote(envelope.displayName.ja)),\"zh\":\(quote(envelope.displayName.zh))}"
        fields += [
            "\"displayName\":\(name)",
            "\"kind\":\(quote(envelope.kind.rawValue))",
            "\"payload\":\(try canonicalPayload(envelope.payload))",
            "\"schema\":1",
        ]
        return Data(("{" + fields.sorted().joined(separator: ",") + "}").utf8)
    }

    public static func encodeRequest(_ envelope: ShareEnvelope) throws -> Data {
        try Gzip.compress(canonicalEnvelope(envelope, includeCreatedAt: false), maximumOutput: maximumCompressedBytes)
    }

    public static func decodeBlob(_ compressed: Data, expectedSHA256: String) throws -> ShareEnvelope {
        guard compressed.count <= maximumCompressedBytes else { throw ShareValidationError.compressedSizeExceeded }
        guard isHash(expectedSHA256), constantTimeEqual(sha256(compressed), expectedSHA256) else {
            throw ShareValidationError.invalidHash
        }
        let expanded = try Gzip.decompress(compressed, maximumOutput: maximumUncompressedBytes)
        let value = try StrictJSON.parse(
            expanded,
            maxDepth: JSONMaximumDepth,
            maxEntries: JSONMaximumEntries,
            maxStringBytes: maximumUncompressedBytes
        )
        let root = try object(value, keys: ["schema", "kind", "displayName", "payload", "contentHash", "createdAt"])
        guard try integer(root, "schema") == 1 else { throw ShareValidationError.unsupportedSchema }
        guard let kind = ShareKind(rawValue: try string(root, "kind")) else {
            throw ShareValidationError.invalidPayload
        }
        let nameObject = try object(try required(root, "displayName"), keys: ["zh", "ja"])
        let names = try normalizeNames(kind: kind, zh: string(nameObject, "zh"), ja: string(nameObject, "ja"))
        let payloadObject = try required(root, "payload")
        let payload = try decodePayload(kind: kind, value: payloadObject)
        let suppliedHash = try string(root, "contentHash")
        guard isHash(suppliedHash) else { throw ShareValidationError.invalidHash }
        let calculatedHash = try contentHash(kind: kind, names: names, payload: payload)
        guard constantTimeEqual(suppliedHash, calculatedHash) else { throw ShareValidationError.invalidHash }
        let dateText = try string(root, "createdAt")
        guard let date = parseDate(dateText) else { throw ShareValidationError.invalidDate }
        return ShareEnvelope(
            kind: kind,
            displayName: names,
            payload: payload,
            contentHash: suppliedHash,
            createdAt: date
        )
    }

    public static func validateJSON(_ text: String) throws {
        try StrictJSON.validate(
            text,
            maxDepth: JSONMaximumDepth,
            maxEntries: JSONMaximumEntries,
            maxStringBytes: maximumSourceBytes
        )
    }

    public static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func build(names: ShareDisplayName, payload: SharePayload) throws -> ShareEnvelope {
        let normalized = try normalizeNames(kind: payload.kind, zh: names.zh, ja: names.ja)
        try validatePayload(payload)
        let hash = try contentHash(kind: payload.kind, names: normalized, payload: payload)
        return ShareEnvelope(kind: payload.kind, displayName: normalized, payload: payload, contentHash: hash)
    }

    private static func validate(_ envelope: ShareEnvelope, requireCreatedAt: Bool) throws {
        guard envelope.schema == 1 else { throw ShareValidationError.unsupportedSchema }
        guard envelope.kind == envelope.payload.kind else { throw ShareValidationError.kindMismatch }
        _ = try normalizeNames(kind: envelope.kind, zh: envelope.displayName.zh, ja: envelope.displayName.ja)
        try validatePayload(envelope.payload)
        guard isHash(envelope.contentHash),
            constantTimeEqual(
                envelope.contentHash,
                try contentHash(kind: envelope.kind, names: envelope.displayName, payload: envelope.payload)
            )
        else { throw ShareValidationError.invalidHash }
        if requireCreatedAt, envelope.createdAt == nil { throw ShareValidationError.invalidDate }
    }

    private static func validatePayload(_ payload: SharePayload) throws {
        switch payload {
        case let .effect(effect):
            guard effect.editorSchema == editorSchema,
                effect.programSchema == programSchema,
                effect.source.isEmpty == false,
                effect.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                effect.source.utf8.count <= maximumSourceBytes,
                containsForbiddenSourceText(effect.source) == false
            else {
                throw ShareValidationError.invalidPayload
            }
            if effect.sourceKind == .blocks { try validateJSON(effect.source) }
        case let .palette(palette):
            guard palette.hex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil,
                (1...maximumAvatarBytes).contains(palette.avatarWebP.count),
                isHash(palette.avatarSHA256),
                constantTimeEqual(sha256(palette.avatarWebP), palette.avatarSHA256),
                isWebP96(palette.avatarWebP)
            else {
                throw ShareValidationError.invalidPayload
            }
        }
    }

    private static func decodePayload(kind: ShareKind, value: JSONValue) throws -> SharePayload {
        switch kind {
        case .effect:
            let object = try object(value, keys: ["sourceKind", "editorSchema", "programSchema", "source"])
            guard let sourceKind = EffectSourceKind(rawValue: try string(object, "sourceKind")) else {
                throw ShareValidationError.invalidPayload
            }
            let payload = EffectSharePayload(
                sourceKind: sourceKind,
                editorSchema: try integer(object, "editorSchema"),
                programSchema: try integer(object, "programSchema"),
                source: try string(object, "source")
            )
            try validatePayload(.effect(payload))
            return .effect(payload)
        case .palette:
            let object = try object(value, keys: ["hex", "avatarWebpBase64", "avatarSha256"])
            let base64 = try string(object, "avatarWebpBase64")
            guard isCanonicalBase64(base64), let avatar = Data(base64Encoded: base64) else {
                throw ShareValidationError.invalidPayload
            }
            let payload = PaletteSharePayload(
                hex: try string(object, "hex"),
                avatarWebP: avatar,
                avatarSHA256: try string(object, "avatarSha256")
            )
            try validatePayload(.palette(payload))
            return .palette(payload)
        }
    }

    private static func canonicalPayload(_ payload: SharePayload) throws -> String {
        let fields: [String]
        switch payload {
        case let .effect(effect):
            fields = [
                "\"editorSchema\":\(effect.editorSchema)",
                "\"programSchema\":\(effect.programSchema)",
                "\"source\":\(quote(effect.source))",
                "\"sourceKind\":\(quote(effect.sourceKind.rawValue))",
            ]
        case let .palette(palette):
            fields = [
                "\"avatarSha256\":\(quote(palette.avatarSHA256))",
                "\"avatarWebpBase64\":\(quote(palette.avatarWebP.base64EncodedString()))",
                "\"hex\":\(quote(palette.hex))",
            ]
        }
        return "{" + fields.sorted().joined(separator: ",") + "}"
    }

    private static func normalizeNames(kind: ShareKind, zh: String, ja: String) throws -> ShareDisplayName {
        let limit = kind == .effect ? 64 : 32
        func normalize(_ value: String) throws -> String {
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            guard result.count <= limit, containsForbiddenText(result) == false else {
                throw ShareValidationError.invalidDisplayName
            }
            return result
        }
        let names = try ShareDisplayName(zh: normalize(zh), ja: normalize(ja))
        guard names.zh.isEmpty == false || names.ja.isEmpty == false else {
            throw ShareValidationError.invalidDisplayName
        }
        return names
    }

    private static func containsForbiddenText(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            let code = scalar.value
            return code <= 0x1f || code == 0x7f || (0x202A...0x202E).contains(code) || (0x2066...0x2069).contains(code)
        }
    }

    /// Source text follows the Android contract: line formatting is allowed,
    /// while non-text controls and bidirectional overrides remain forbidden.
    private static func containsForbiddenSourceText(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            let code = scalar.value
            return code <= 0x08 || code == 0x0B || code == 0x0C
                || (0x0E...0x1F).contains(code) || code == 0x7F
                || (0x202A...0x202E).contains(code) || (0x2066...0x2069).contains(code)
        }
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 0x08: result += "\\b"
            case 0x0c: result += "\\f"
            case 0x0a: result += "\\n"
            case 0x0d: result += "\\r"
            case 0x09: result += "\\t"
            case 0x00...0x1f: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    private static func isCanonicalBase64(_ value: String) -> Bool {
        guard value.isEmpty == false, value.utf8.count.isMultiple(of: 4),
            value.range(of: "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$", options: .regularExpression) != nil,
            let decoded = Data(base64Encoded: value)
        else { return false }
        return decoded.base64EncodedString() == value
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    private static func isWebP96(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 30,
            String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
            String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP",
            littleEndian32(bytes, at: 4) == UInt32(bytes.count - 8)
        else { return false }
        let chunkLength = Int(littleEndian32(bytes, at: 16))
        guard chunkLength <= bytes.count - 20,
            chunkLength + (chunkLength & 1) <= bytes.count - 20
        else { return false }
        let type = String(bytes: bytes[12..<16], encoding: .ascii)
        switch type {
        case "VP8X":
            guard chunkLength >= 10 else { return false }
            let width = 1 + Int(bytes[24]) + (Int(bytes[25]) << 8) + (Int(bytes[26]) << 16)
            let height = 1 + Int(bytes[27]) + (Int(bytes[28]) << 8) + (Int(bytes[29]) << 16)
            return width == 96 && height == 96
        case "VP8L":
            guard chunkLength >= 5, bytes[20] == 0x2f else { return false }
            let bits = UInt32(bytes[21]) | (UInt32(bytes[22]) << 8) | (UInt32(bytes[23]) << 16) | (UInt32(bytes[24]) << 24)
            return Int(bits & 0x3fff) + 1 == 96 && Int((bits >> 14) & 0x3fff) + 1 == 96
        case "VP8 ":
            guard chunkLength >= 10, bytes[23] == 0x9d, bytes[24] == 0x01, bytes[25] == 0x2a else { return false }
            let width = (Int(bytes[26]) | (Int(bytes[27]) << 8)) & 0x3fff
            let height = (Int(bytes[28]) | (Int(bytes[29]) << 8)) & 0x3fff
            return width == 96 && height == 96
        default: return false
        }
    }

    private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func object(_ value: JSONValue, keys: Set<String>) throws -> [String: JSONValue] {
        guard case let .object(object) = value else { throw ShareValidationError.invalidPayload }
        guard Set(object.keys) == keys else { throw ShareValidationError.unknownOrMissingField }
        return object
    }

    private static func required(_ object: [String: JSONValue], _ key: String) throws -> JSONValue {
        guard let value = object[key] else { throw ShareValidationError.unknownOrMissingField }
        return value
    }

    private static func string(_ object: [String: JSONValue], _ key: String) throws -> String {
        guard case let .string(value) = try required(object, key) else { throw ShareValidationError.invalidPayload }
        return value
    }

    private static func integer(_ object: [String: JSONValue], _ key: String) throws -> Int {
        guard case let .integer(value) = try required(object, key) else { throw ShareValidationError.invalidPayload }
        return value
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
