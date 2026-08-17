import CryptoKit
import Foundation

public struct EffectProgram: Equatable, Sendable {
    public let id: String
    public let nameZh: String
    public let nameJa: String
    public let workspaceJSON: String
    public let astJSON: String
    public let astSHA256: String
    public let blockCount: Int
    public let estimatedDurationMilliseconds: Int64?
    public let createdAt: Int64
    public let updatedAt: Int64
    public let editorSchema: Int
    public let programSchema: Int
    public let sourceKind: EffectSourceKind
    public let scriptSource: String

    public init(
        id: String,
        nameZh: String,
        nameJa: String,
        workspaceJSON: String = "",
        astJSON: String = "",
        astSHA256: String = "",
        blockCount: Int = 0,
        estimatedDurationMilliseconds: Int64? = nil,
        createdAt: Int64,
        updatedAt: Int64,
        editorSchema: Int = EffectProgramSchemas.editor,
        programSchema: Int = EffectProgramSchemas.program,
        sourceKind: EffectSourceKind = .blocks,
        scriptSource: String = ""
    ) {
        self.id = id
        self.nameZh = nameZh
        self.nameJa = nameJa
        self.workspaceJSON = workspaceJSON
        self.astJSON = astJSON
        self.astSHA256 = astSHA256
        self.blockCount = blockCount
        self.estimatedDurationMilliseconds = estimatedDurationMilliseconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.editorSchema = editorSchema
        self.programSchema = programSchema
        self.sourceKind = sourceKind
        self.scriptSource = scriptSource
    }
}

public enum EffectImportConflictStrategy: Sendable { case copy, overwrite, skip }

public struct EffectImportPreview: Equatable, Sendable {
    public let programs: [EffectProgram]
    public let errors: [String]
    public let conflictIDs: Set<String>

    public init(programs: [EffectProgram], errors: [String], conflictIDs: Set<String>) {
        self.programs = programs
        self.errors = errors
        self.conflictIDs = conflictIDs
    }
}

public enum EffectProgramError: Error, Equatable, Sendable {
    case invalidUTF8
    case invalidJSON
    case duplicateJSONKey(String)
    case JSONLimitExceeded
    case fileTooLarge
    case unsupportedSchema(Int64?)
    case invalidKind(String?)
    case unknownField(String)
    case missingField(String)
    case invalidField(String)
    case emptyName
    case emptySource
    case sourceTooLarge
    case tooManyPrograms
    case duplicateProgramID(String)
    case programNotFound(String)
    case revisionConflict
    case storageCorrupt
}

extension EffectProgramError {
    public var code: String {
        switch self {
        case .invalidUTF8: "EFFECT_IMPORT_INVALID_UTF8"
        case .invalidJSON: "EFFECT_IMPORT_INVALID_JSON"
        case .duplicateJSONKey: "EFFECT_IMPORT_DUPLICATE_JSON_KEY"
        case .JSONLimitExceeded: "EFFECT_IMPORT_JSON_LIMIT_EXCEEDED"
        case .fileTooLarge: "EFFECT_IMPORT_FILE_TOO_LARGE"
        case .unsupportedSchema: "EFFECT_IMPORT_UNSUPPORTED_SCHEMA"
        case .invalidKind: "EFFECT_IMPORT_INVALID_KIND"
        case .unknownField: "EFFECT_IMPORT_UNKNOWN_FIELD"
        case .missingField: "EFFECT_IMPORT_MISSING_FIELD"
        case .invalidField: "EFFECT_IMPORT_INVALID_FIELD"
        case .emptyName: "EFFECT_PROGRAM_EMPTY_NAME"
        case .emptySource: "EFFECT_PROGRAM_EMPTY_SOURCE"
        case .sourceTooLarge: "EFFECT_PROGRAM_SOURCE_TOO_LARGE"
        case .tooManyPrograms: "EFFECT_PROGRAM_LIMIT_EXCEEDED"
        case .duplicateProgramID: "EFFECT_PROGRAM_DUPLICATE_ID"
        case .programNotFound: "EFFECT_PROGRAM_NOT_FOUND"
        case .revisionConflict: "EFFECT_PROGRAM_REVISION_CONFLICT"
        case .storageCorrupt: "EFFECT_PROGRAM_STORAGE_CORRUPT"
        }
    }
}

public enum EffectProgramCompiler: Sendable {
    public static func compile(_ program: EffectProgram) throws -> CompiledEffect {
        switch program.sourceKind {
        case .blocks: try EffectCompiler.compile(blocklyJSON: program.workspaceJSON)
        case .script: try EffectScriptCompiler.compile(program.scriptSource)
        }
    }

    public static func normalise(_ program: EffectProgram, now: Int64) throws -> EffectProgram {
        let compiled = try compile(program)
        return EffectProgram(
            id: program.id,
            nameZh: program.nameZh,
            nameJa: program.nameJa,
            workspaceJSON: program.workspaceJSON,
            astJSON: EffectCompiler.canonicalJSON(compiled),
            astSHA256: compiled.astSHA256,
            blockCount: compiled.blockCount,
            estimatedDurationMilliseconds: compiled.estimatedDurationMilliseconds,
            createdAt: program.createdAt,
            updatedAt: now,
            editorSchema: EffectProgramSchemas.editor,
            programSchema: EffectProgramSchemas.program,
            sourceKind: program.sourceKind,
            scriptSource: program.scriptSource
        )
    }
}

public enum EffectProgramTransfer: Sendable {
    public static let maximumFileBytes = 2 * 1024 * 1024
    public static let maximumPrograms = 50
    public static let appVersion = "4.2.0"
    private static let singleKind = "maurya-effect"
    private static let bundleKind = "maurya-effect-bundle"
    private static let programFields: Set<String> = [
        "id", "nameZh", "nameJa", "sourceKind", "workspaceJson", "scriptSource", "astJson",
        "astSha256", "blockCount", "estimatedDurationMs", "createdAt", "updatedAt", "editorSchema", "programSchema",
    ]

    public static func exportSingle(_ program: EffectProgram) throws -> Data {
        try encodeJSON(["schema": 1, "kind": singleKind, "exportedBy": exportedBy(), "program": encodeObject(program)], pretty: true)
    }

    public static func exportBundle(_ programs: [EffectProgram]) throws -> Data {
        guard programs.count <= maximumPrograms else { throw EffectProgramError.tooManyPrograms }
        return try encodeJSON(
            ["schema": 1, "kind": bundleKind, "exportedBy": exportedBy(), "programs": programs.map(encodeObject)], pretty: true)
    }

    public static func preview(
        _ data: Data,
        existingIDs: Set<String>,
        now: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
        makeID: @Sendable () -> String = { UUID().uuidString }
    ) throws -> EffectImportPreview {
        guard data.count <= maximumFileBytes else { throw EffectProgramError.fileTooLarge }
        guard case let .object(root) = try EffectStrictJSON.parse(data) else { throw EffectProgramError.invalidJSON }
        let kind = try rootString(root, "kind")
        let allowedRoot: Set<String>
        let rawPrograms: [EffectJSONValue]
        switch kind {
        case singleKind:
            allowedRoot = ["schema", "kind", "exportedBy", "program"]
            rawPrograms = [try required(root, "program")]
        case bundleKind:
            allowedRoot = ["schema", "kind", "exportedBy", "programs"]
            guard case let .array(values) = try required(root, "programs") else { throw EffectProgramError.invalidField("programs") }
            guard values.count <= maximumPrograms else { throw EffectProgramError.tooManyPrograms }
            rawPrograms = values
        default: throw EffectProgramError.invalidKind(kind)
        }
        try rejectUnknown(root, allowed: allowedRoot)
        guard case let .integer(schema)? = root["schema"], schema == 1 else {
            let schema: Int64? = if case let .integer(value)? = root["schema"] { value } else { nil }
            throw EffectProgramError.unsupportedSchema(schema)
        }
        if let exportedBy = root["exportedBy"] {
            guard case let .object(object) = exportedBy else { throw EffectProgramError.invalidField("exportedBy") }
            try rejectUnknown(object, allowed: ["appVersion", "programSchema"])
            if object["appVersion"] != nil { _ = try string(object, "appVersion", default: "") }
            if object["programSchema"] != nil { _ = try integer(object, "programSchema", default: 0) }
        }

        var programs: [EffectProgram] = []
        var errors: [String] = []
        var seen = Set<String>()
        for (offset, raw) in rawPrograms.enumerated() {
            do {
                guard case let .object(object) = raw else { throw EffectProgramError.invalidField("program") }
                let decoded = try decodeObject(object, recompile: true, now: now(), makeID: makeID)
                guard seen.insert(decoded.id).inserted else { throw EffectProgramError.duplicateProgramID(decoded.id) }
                programs.append(decoded)
            } catch {
                errors.append("项目\(offset + 1)：\(describe(error))")
            }
        }
        return EffectImportPreview(programs: programs, errors: errors, conflictIDs: Set(programs.map(\.id)).intersection(existingIDs))
    }

    public static func revision(of program: EffectProgram) throws -> String {
        let data = try encodeJSON(encodeObject(program), pretty: false)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encodeRepository(_ programs: [EffectProgram]) throws -> Data {
        try encodeJSON(programs.map(encodeObject), pretty: false)
    }

    static func decodeRepository(_ data: Data, now: Int64, makeID: @Sendable () -> String) throws -> [EffectProgram] {
        guard data.count <= maximumFileBytes else { throw EffectProgramError.fileTooLarge }
        guard case let .array(values) = try EffectStrictJSON.parse(data), values.count <= maximumPrograms else {
            throw EffectProgramError.storageCorrupt
        }
        var result: [EffectProgram] = []
        var ids = Set<String>()
        for value in values {
            guard case let .object(object) = value else { throw EffectProgramError.storageCorrupt }
            let decoded = try decodeObject(object, recompile: false, now: now, makeID: makeID)
            let normalised = try EffectProgramCompiler.normalise(decoded, now: decoded.updatedAt)
            guard ids.insert(decoded.id).inserted else { throw EffectProgramError.duplicateProgramID(decoded.id) }
            result.append(normalised)
        }
        return result
    }

    static func encodeObject(_ program: EffectProgram) -> [String: Any] {
        [
            "id": program.id, "nameZh": program.nameZh, "nameJa": program.nameJa,
            "sourceKind": program.sourceKind.rawValue.lowercased(), "workspaceJson": program.workspaceJSON,
            "scriptSource": program.scriptSource, "astJson": program.astJSON, "astSha256": program.astSHA256,
            "blockCount": program.blockCount, "estimatedDurationMs": program.estimatedDurationMilliseconds ?? NSNull(),
            "createdAt": program.createdAt, "updatedAt": program.updatedAt, "editorSchema": program.editorSchema,
            "programSchema": program.programSchema,
        ]
    }

    private static func decodeObject(
        _ object: [String: EffectJSONValue], recompile: Bool, now: Int64, makeID: @Sendable () -> String
    ) throws -> EffectProgram {
        try rejectUnknown(object, allowed: programFields)
        let sourceRaw = try string(object, "sourceKind", default: "blocks").lowercased()
        let kind: EffectSourceKind =
            switch sourceRaw {
            case "blocks": .blocks
            case "script": .script
            default: throw EffectProgramError.invalidField("sourceKind")
            }
        let rawID = try string(object, "id", default: "")
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? makeID() : rawID
        let nameZh = String(try string(object, "nameZh", default: "导入灯效").prefix(64))
        let nameJa = String(try string(object, "nameJa", default: "インポートエフェクト").prefix(64))
        guard
            !nameZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !nameJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw EffectProgramError.emptyName }
        let workspace = try string(object, "workspaceJson", default: "")
        let script = try string(object, "scriptSource", default: "")
        let source = kind == .blocks ? workspace : script
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EffectProgramError.emptySource }
        guard source.utf8.count <= EffectScriptCompiler.maximumSourceBytes else { throw EffectProgramError.sourceTooLarge }
        let estimated: Int64? =
            switch object["estimatedDurationMs"] {
            case nil, .some(.null): nil
            case let .some(.integer(value)): value
            default: throw EffectProgramError.invalidField("estimatedDurationMs")
            }
        let decoded = EffectProgram(
            id: id, nameZh: nameZh, nameJa: nameJa, workspaceJSON: workspace,
            astJSON: try string(object, "astJson", default: ""), astSHA256: try string(object, "astSha256", default: ""),
            blockCount: try checkedInt(object, "blockCount", default: 0), estimatedDurationMilliseconds: estimated,
            createdAt: try integer(object, "createdAt", default: now), updatedAt: try integer(object, "updatedAt", default: now),
            editorSchema: try checkedInt(object, "editorSchema", default: 1),
            programSchema: try checkedInt(object, "programSchema", default: 1),
            sourceKind: kind, scriptSource: script
        )
        return recompile ? try EffectProgramCompiler.normalise(decoded, now: now) : decoded
    }

    private static func exportedBy() -> [String: Any] { ["appVersion": appVersion, "programSchema": EffectProgramSchemas.program] }
    private static func encodeJSON(_ object: Any, pretty: Bool) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }
    private static func required(_ object: [String: EffectJSONValue], _ key: String) throws -> EffectJSONValue {
        guard let value = object[key] else { throw EffectProgramError.missingField(key) }; return value
    }
    private static func rootString(_ object: [String: EffectJSONValue], _ key: String) throws -> String {
        try string(object, key, default: "")
    }
    private static func string(_ object: [String: EffectJSONValue], _ key: String, default fallback: String) throws -> String {
        guard let value = object[key] else { return fallback }
        guard case let .string(result) = value else { throw EffectProgramError.invalidField(key) }; return result
    }
    private static func integer(_ object: [String: EffectJSONValue], _ key: String, default fallback: Int64) throws -> Int64 {
        guard let value = object[key] else { return fallback }
        guard case let .integer(result) = value else { throw EffectProgramError.invalidField(key) }; return result
    }
    private static func checkedInt(_ object: [String: EffectJSONValue], _ key: String, default fallback: Int) throws -> Int {
        let value = try integer(object, key, default: Int64(fallback))
        guard let result = Int(exactly: value) else { throw EffectProgramError.invalidField(key) }; return result
    }
    private static func rejectUnknown(_ object: [String: EffectJSONValue], allowed: Set<String>) throws {
        if let key = object.keys.first(where: { !allowed.contains($0) }) { throw EffectProgramError.unknownField(key) }
    }
    private static func describe(_ error: any Error) -> String {
        if let compile = error as? EffectCompileError, let issue = compile.issues.first {
            return issue.code
        }
        if let program = error as? EffectProgramError { return program.code }
        return "EFFECT_IMPORT_COMPILE_FAILED"
    }
}
