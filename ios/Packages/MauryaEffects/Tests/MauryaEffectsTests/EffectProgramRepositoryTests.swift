import Foundation
import Testing
import os

@testable import MauryaEffects

struct EffectProgramRepositoryTests {
    @Test func missingStoreCreatesStableAndroidExampleIDs() async throws {
        let repository = try EffectProgramRepository(storage: MemoryStorage(), clock: { 1_000 })
        #expect(repository.recovery == .createdDefaults)
        #expect(await repository.programs().map(\.id) == ["example-rgb", "example-rainbow"])
        #expect(await repository.programs().allSatisfy { $0.sourceKind == .blocks && !$0.workspaceJSON.isEmpty })
    }

    @Test func actorCRUDCopyAndOptimisticRevision() async throws {
        let storage = MemoryStorage()
        let repository = try EffectProgramRepository(storage: storage, defaults: [], clock: { 2_000 }, makeID: { "copy-id" })
        let inserted = try await repository.upsert(try fixture(id: "one", colour: "#FF0000"))
        #expect(inserted.program.id == "one")
        #expect(try await repository.list().count == 1)

        let changed = try fixture(id: "one", colour: "#00FF00")
        let updated = try await repository.upsert(changed, expectedRevision: inserted.revision)
        #expect(updated.revision != inserted.revision)
        await #expect(throws: EffectProgramError.revisionConflict) {
            try await repository.upsert(changed, expectedRevision: inserted.revision)
        }

        let copy = try await repository.copy(id: "one")
        #expect(copy.program.id == "copy-id")
        #expect(copy.program.nameZh.hasSuffix(" 副本"))
        #expect(copy.program.nameJa.hasSuffix(" コピー"))
        #expect(copy.program.createdAt == 2_000)
        _ = try await repository.delete(id: "copy-id", expectedRevision: copy.revision)
        #expect(await repository.programs().map(\.id) == ["one"])
    }

    @Test func importStrategiesMatchAndroid() async throws {
        let storage = MemoryStorage()
        let repository = try EffectProgramRepository(
            storage: storage, defaults: [try fixture(id: "same", colour: "#FF0000")], clock: { 5_000 }, makeID: { "copy" })
        let incoming = try fixture(id: "same", colour: "#0000FF")
        let preview = try EffectProgramTransfer.preview(
            try EffectProgramTransfer.exportSingle(incoming), existingIDs: ["same"], now: { 4_000 })
        _ = try await repository.applyImport(preview, strategy: .skip)
        #expect(await repository.programs().count == 1)
        _ = try await repository.applyImport(preview, strategy: .copy)
        #expect(await repository.programs().map(\.id) == ["same", "copy"])
    }

    @Test func failedAtomicWriteDoesNotMutateActorState() async throws {
        let storage = MemoryStorage()
        let repository = try EffectProgramRepository(storage: storage, defaults: [try fixture(id: "existing", colour: "#FF0000")])
        storage.failWrites()
        await #expect(throws: MemoryStorage.Failure.self) { try await repository.upsert(try fixture(id: "new", colour: "#00FF00")) }
        #expect(await repository.programs().map(\.id) == ["existing"])
    }

    @Test func corruptFileIsQuarantinedAndDefaultsAreRecovered() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MauryaEffects-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storage = FileEffectProgramStorage(directoryURL: directory)
        try Data(#"[{"id":"broken","unknown":true}]"#.utf8).write(to: storage.fileURL)
        let repository = try EffectProgramRepository(storage: storage, defaults: [try fixture(id: "fallback", colour: "#FF0000")])
        guard case let .replacedCorruptFile(url) = repository.recovery else { Issue.record("Expected corruption recovery"); return }
        #expect(url != nil)
        #expect(await repository.programs().map(\.id) == ["fallback"])
        #expect(try storage.read() != nil)
    }

    @Test func fileStorageAtomicallyReplacesCompleteRepositoryDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MauryaEffects-atomic-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileEffectProgramStorage(directoryURL: directory)
        let first = try EffectProgramTransfer.encodeRepository([fixture(id: "first", colour: "#FF0000")])
        let second = try EffectProgramTransfer.encodeRepository([fixture(id: "second", colour: "#0000FF")])
        try storage.replaceAtomically(with: first)
        try storage.replaceAtomically(with: second)
        let persisted = try #require(try storage.read())
        #expect(try EffectProgramTransfer.decodeRepository(persisted, now: 1_000, makeID: { "unused" }).map(\.id) == ["second"])
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(siblings == ["effect_programs.json"])
    }

    @Test func fiftyProgramLimitIsEnforcedBeforeWrite() async throws {
        let defaults = try (0..<50).map { try fixture(id: "p\($0)", colour: "#FF0000") }
        let repository = try EffectProgramRepository(storage: MemoryStorage(), defaults: defaults)
        await #expect(throws: EffectProgramError.tooManyPrograms) {
            try await repository.upsert(try fixture(id: "overflow", colour: "#00FF00"))
        }
        #expect(await repository.programs().count == 50)
    }

    private func fixture(id: String, colour: String) throws -> EffectProgram {
        try EffectProgramCompiler.normalise(
            EffectProgram(
                id: id, nameZh: "名称", nameJa: "名前", createdAt: 1_000, updatedAt: 1_000,
                sourceKind: .script, scriptSource: "effect \"x\" { all.color(\"\(colour)\"); wait(100ms); }"
            ),
            now: 1_000
        )
    }
}

private final class MemoryStorage: EffectProgramStorage, Sendable {
    enum Failure: Error { case write }
    struct State: Sendable { var data: Data?; var shouldFail = false }
    private let state = OSAllocatedUnfairLock(initialState: State(data: nil))

    func read() throws -> Data? { state.withLock { $0.data } }
    func replaceAtomically(with data: Data) throws {
        try state.withLock {
            if $0.shouldFail { throw Failure.write }
            $0.data = data
        }
    }
    func quarantineCorruptFile() throws -> URL? { state.withLock { $0.data = nil }; return nil }
    func failWrites() { state.withLock { $0.shouldFail = true } }
}
