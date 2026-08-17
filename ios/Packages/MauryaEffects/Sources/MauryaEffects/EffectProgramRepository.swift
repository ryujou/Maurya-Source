import Foundation

public protocol EffectProgramStorage: Sendable {
    func read() throws -> Data?
    func replaceAtomically(with data: Data) throws
    @discardableResult func quarantineCorruptFile() throws -> URL?
}

public struct FileEffectProgramStorage: EffectProgramStorage, Sendable {
    public let fileURL: URL

    public init(directoryURL: URL, fileName: String = "effect_programs.json") {
        fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    public func read() throws -> Data? {
        do { return try Data(contentsOf: fileURL) } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public func replaceAtomically(with data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult public func quarantineCorruptFile() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fileURL, to: destination)
        return destination
    }
}

public struct EffectProgramRecord: Equatable, Sendable {
    public let program: EffectProgram
    public let revision: String

    public init(program: EffectProgram, revision: String) {
        self.program = program
        self.revision = revision
    }
}

public enum EffectProgramRecovery: Equatable, Sendable {
    case none
    case createdDefaults
    case replacedCorruptFile(quarantineURL: URL?)
}

public actor EffectProgramRepository {
    public typealias Clock = @Sendable () -> Int64
    public typealias IDGenerator = @Sendable () -> String

    private let storage: any EffectProgramStorage
    private let clock: Clock
    private let makeID: IDGenerator
    private var values: [EffectProgram]
    public nonisolated let recovery: EffectProgramRecovery

    public init(
        storage: any EffectProgramStorage,
        defaults: [EffectProgram]? = nil,
        clock: @escaping Clock = { Int64(Date().timeIntervalSince1970 * 1_000) },
        makeID: @escaping IDGenerator = { UUID().uuidString }
    ) throws {
        self.storage = storage
        self.clock = clock
        self.makeID = makeID
        let now = clock()
        let fallback = try defaults ?? Self.androidExamples(now: now)
        let initialValues: [EffectProgram]
        let initialRecovery: EffectProgramRecovery
        if let data = try storage.read() {
            do {
                initialValues = try EffectProgramTransfer.decodeRepository(data, now: now, makeID: makeID)
                initialRecovery = .none
            } catch {
                let quarantined = try? storage.quarantineCorruptFile()
                initialValues = fallback
                initialRecovery = .replacedCorruptFile(quarantineURL: quarantined ?? nil)
            }
            try storage.replaceAtomically(with: EffectProgramTransfer.encodeRepository(initialValues))
        } else {
            initialValues = fallback
            initialRecovery = .createdDefaults
            try storage.replaceAtomically(with: EffectProgramTransfer.encodeRepository(fallback))
        }
        values = initialValues
        recovery = initialRecovery
    }

    public func list() throws -> [EffectProgramRecord] { try values.map(Self.record) }
    public func programs() -> [EffectProgram] { values }

    @discardableResult public func upsert(_ program: EffectProgram, expectedRevision: String? = nil) throws -> EffectProgramRecord {
        var next = values
        let index = next.firstIndex { $0.id == program.id }
        if let index {
            if let expectedRevision, try EffectProgramTransfer.revision(of: next[index]) != expectedRevision {
                throw EffectProgramError.revisionConflict
            }
            next[index] = try EffectProgramCompiler.normalise(program, now: clock())
        } else {
            guard expectedRevision == nil else { throw EffectProgramError.revisionConflict }
            guard next.count < EffectProgramTransfer.maximumPrograms else { throw EffectProgramError.tooManyPrograms }
            next.append(try EffectProgramCompiler.normalise(program, now: clock()))
        }
        try commit(next)
        return try Self.record(next[index ?? (next.count - 1)])
    }

    @discardableResult public func copy(id: String) throws -> EffectProgramRecord {
        guard let source = values.first(where: { $0.id == id }) else { throw EffectProgramError.programNotFound(id) }
        guard values.count < EffectProgramTransfer.maximumPrograms else { throw EffectProgramError.tooManyPrograms }
        let now = clock()
        let duplicate = EffectProgram(
            id: makeID(), nameZh: "\(source.nameZh) 副本", nameJa: "\(source.nameJa) コピー",
            workspaceJSON: source.workspaceJSON, astJSON: source.astJSON, astSHA256: source.astSHA256,
            blockCount: source.blockCount, estimatedDurationMilliseconds: source.estimatedDurationMilliseconds,
            createdAt: now, updatedAt: now, editorSchema: source.editorSchema, programSchema: source.programSchema,
            sourceKind: source.sourceKind, scriptSource: source.scriptSource
        )
        var next = values; next.append(duplicate)
        try commit(next)
        return try Self.record(duplicate)
    }

    @discardableResult public func delete(id: String, expectedRevision: String? = nil) throws -> [EffectProgramRecord] {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return try list() }
        if let expectedRevision, try EffectProgramTransfer.revision(of: values[index]) != expectedRevision {
            throw EffectProgramError.revisionConflict
        }
        var next = values; next.remove(at: index)
        try commit(next)
        return try next.map(Self.record)
    }

    public func exportProgram(id: String) throws -> Data {
        guard let program = values.first(where: { $0.id == id }) else { throw EffectProgramError.programNotFound(id) }
        return try EffectProgramTransfer.exportSingle(program)
    }

    public func exportAll() throws -> Data { try EffectProgramTransfer.exportBundle(values) }

    public func previewImport(_ data: Data) throws -> EffectImportPreview {
        try EffectProgramTransfer.preview(data, existingIDs: Set(values.map(\.id)), now: clock, makeID: makeID)
    }

    @discardableResult public func applyImport(_ preview: EffectImportPreview, strategy: EffectImportConflictStrategy) throws
        -> [EffectProgramRecord]
    {
        var next = values
        for importedValue in preview.programs {
            let imported = try EffectProgramCompiler.normalise(importedValue, now: importedValue.updatedAt)
            if let index = next.firstIndex(where: { $0.id == imported.id }) {
                switch strategy {
                case .skip: continue
                case .overwrite: next[index] = imported
                case .copy:
                    let now = clock()
                    next.append(
                        EffectProgram(
                            id: makeID(), nameZh: "\(imported.nameZh) 副本", nameJa: "\(imported.nameJa) コピー",
                            workspaceJSON: imported.workspaceJSON, astJSON: imported.astJSON, astSHA256: imported.astSHA256,
                            blockCount: imported.blockCount, estimatedDurationMilliseconds: imported.estimatedDurationMilliseconds,
                            createdAt: now, updatedAt: now, editorSchema: imported.editorSchema, programSchema: imported.programSchema,
                            sourceKind: imported.sourceKind, scriptSource: imported.scriptSource
                        ))
                }
            } else {
                next.append(imported)
            }
        }
        guard next.count <= EffectProgramTransfer.maximumPrograms else { throw EffectProgramError.tooManyPrograms }
        guard Set(next.map(\.id)).count == next.count else { throw EffectProgramError.duplicateProgramID("import") }
        try commit(next)
        return try next.map(Self.record)
    }

    private func commit(_ next: [EffectProgram]) throws {
        let data = try EffectProgramTransfer.encodeRepository(next)
        try storage.replaceAtomically(with: data)
        values = next
    }

    private static func record(_ program: EffectProgram) throws -> EffectProgramRecord {
        try EffectProgramRecord(program: program, revision: EffectProgramTransfer.revision(of: program))
    }

    private static func androidExamples(now: Int64) throws -> [EffectProgram] {
        let workspaces = [
            (
                "example-rgb", "红→绿→蓝", "赤→緑→青",
                ##"{"blocks":{"languageVersion":0,"blocks":[{"type":"maurya_start","id":"example-rgb-start","next":{"block":{"type":"maurya_set_color","id":"example-rgb-red","fields":{"TARGET":"ALL","COLOR":"#ff0000"},"next":{"block":{"type":"maurya_wait","id":"example-rgb-wait","fields":{"DURATION":500,"UNIT":"MS"},"next":{"block":{"type":"maurya_fade","id":"example-rgb-green","fields":{"TARGET":"ALL","COLOR":"#00ff00","DURATION":1500},"next":{"block":{"type":"maurya_fade","id":"example-rgb-blue","fields":{"TARGET":"ALL","COLOR":"#0000ff","DURATION":1500}}}}}}}}}}]}}"##
            ),
            (
                "example-rainbow", "无限彩虹", "無限レインボー",
                ##"{"blocks":{"languageVersion":0,"blocks":[{"type":"maurya_start","id":"example-rainbow-start","next":{"block":{"type":"maurya_forever","id":"example-rainbow-loop","inputs":{"DO":{"block":{"type":"maurya_adjust_hsv","id":"example-rainbow-adjust","fields":{"TARGET":"ALL","H":2,"S":0,"V":0},"next":{"block":{"type":"maurya_wait","id":"example-rainbow-wait","fields":{"DURATION":50,"UNIT":"MS"}}}}}}}}}]}}"##
            ),
        ]
        return try workspaces.map { id, zh, ja, workspace in
            try EffectProgramCompiler.normalise(
                EffectProgram(
                    id: id, nameZh: zh, nameJa: ja, workspaceJSON: workspace, createdAt: now, updatedAt: now, sourceKind: .blocks),
                now: now
            )
        }
    }
}
