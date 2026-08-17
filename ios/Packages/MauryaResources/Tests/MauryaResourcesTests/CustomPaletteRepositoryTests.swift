import Foundation
import MauryaResources
import MauryaShare
import Testing

struct CustomPaletteRepositoryTests {
    @Test func saveUpdateDeleteAndSessionUndo() async throws {
        let directory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CustomPaletteRepository(
            storage: FileCustomPaletteStorage(rootURL: directory),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        _ = try await repository.loadAndRepair()
        let firstColor = try #require(RGBHex(rawValue: "#112233"))
        let first = try await repository.save(
            names: PaletteNames(zh: "星", ja: "星"),
            color: firstColor,
            avatarWebP: Fixtures.WebP96()
        )
        #expect(first.revision == 1)
        let updatedColor = try #require(RGBHex(rawValue: "#445566"))
        let updated = try await repository.save(
            existingID: first.id,
            expectedRevision: first.revision,
            names: PaletteNames(zh: "星光", ja: "星"),
            color: updatedColor,
            avatarWebP: Fixtures.WebP96(marker: 1)
        )
        #expect(updated.revision == 2)
        let deletion = try await repository.delete(id: updated.id, expectedRevision: updated.revision)
        #expect(try await repository.snapshot().entries.isEmpty)
        let restored = try await repository.restore(deletion)
        #expect(restored == updated)
    }

    @Test func enforcesFiftyEntryBoundaryAndContentDeduplication() async throws {
        let directory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CustomPaletteRepository(storage: FileCustomPaletteStorage(rootURL: directory))
        _ = try await repository.loadAndRepair()
        let color = try #require(RGBHex(rawValue: "#123456"))
        let first = try await repository.save(
            names: PaletteNames(zh: "颜色0", ja: ""),
            color: color,
            avatarWebP: Fixtures.WebP96()
        )
        do {
            _ = try await repository.save(
                names: PaletteNames(zh: "颜色0", ja: ""),
                color: color,
                avatarWebP: Fixtures.WebP96()
            )
            Issue.record("Expected identical content to be deduplicated.")
        } catch let error as CustomPaletteError {
            #expect(error == .duplicateContent(existingID: first.id))
        }
        for index in 1..<CustomPaletteRepository.maximumEntries {
            _ = try await repository.save(
                names: PaletteNames(zh: "颜色\(index)", ja: ""),
                color: color,
                avatarWebP: Fixtures.WebP96()
            )
        }
        do {
            _ = try await repository.save(
                names: PaletteNames(zh: "第51项", ja: ""),
                color: color,
                avatarWebP: Fixtures.WebP96()
            )
            Issue.record("Expected the 51st item to fail.")
        } catch let error as CustomPaletteError {
            #expect(error == .capacityReached(limit: 50))
        }
    }

    @Test func AndroidBackupRoundTripsAndSharePayloadImports() async throws {
        let firstDirectory = try Fixtures.temporaryDirectory()
        let secondDirectory = try Fixtures.temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let source = CustomPaletteRepository(storage: FileCustomPaletteStorage(rootURL: firstDirectory))
        _ = try await source.loadAndRepair()
        let color = try #require(RGBHex(rawValue: "#39C5BB"))
        let entry = try await source.save(
            names: PaletteNames(zh: "应援色", ja: "応援色"),
            color: color,
            avatarWebP: Fixtures.WebP96()
        )
        let backup = try await source.exportBackup()

        let destination = CustomPaletteRepository(storage: FileCustomPaletteStorage(rootURL: secondDirectory))
        _ = try await destination.loadAndRepair()
        #expect(try await destination.importBackup(backup, conflictPolicy: .overwrite).imported == 1)
        let restored = try #require(try await destination.snapshot().entries.first)
        #expect(restored.names == entry.names)
        let envelope = try entry.makeShareEnvelope(avatarWebP: Fixtures.WebP96())
        guard case let .palette(payload) = envelope.payload else {
            Issue.record("Expected palette payload.")
            return
        }
        let thirdDirectory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: thirdDirectory) }
        let shareDestination = CustomPaletteRepository(storage: FileCustomPaletteStorage(rootURL: thirdDirectory))
        _ = try await shareDestination.loadAndRepair()
        let shared = try await shareDestination.importShare(names: envelope.displayName, payload: payload)
        #expect(shared.avatar.sha256 == payload.avatarSHA256)
    }

    @Test func loadRepairsOrphanAvatarAndRejectsCorruptIndex() async throws {
        let directory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileCustomPaletteStorage(rootURL: directory)
        let orphan = "\(UUID().uuidString.lowercased())-\(String(repeating: "a", count: 64)).webp"
        try storage.writeAvatar(Fixtures.WebP96(), named: orphan)
        let repository = CustomPaletteRepository(storage: storage)
        _ = try await repository.loadAndRepair()
        #expect(try storage.avatarFilenames().isEmpty)

        try Data("not-json".utf8).write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        let corrupt = CustomPaletteRepository(storage: storage)
        do {
            _ = try await corrupt.loadAndRepair()
            Issue.record("Expected corrupt index to fail closed.")
        } catch let error as CustomPaletteError {
            #expect(error == .corruptIndex)
        }
    }

    @Test func diskWriteFailurePropagatesWithoutPublishingState() async throws {
        let directory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockingFile = directory.appendingPathComponent("blocked")
        try Data([1]).write(to: blockingFile)
        let repository = CustomPaletteRepository(
            storage: FileCustomPaletteStorage(rootURL: blockingFile.appendingPathComponent("child"))
        )
        do {
            _ = try await repository.loadAndRepair()
            Issue.record("Expected storage failure.")
        } catch {
            do {
                _ = try await repository.snapshot()
                Issue.record("Failed load must not publish repository state.")
            } catch let stateError as CustomPaletteError {
                #expect(stateError == .corruptIndex)
            }
        }
    }

    @Test func failedIndexCommitCompensatesNewAvatar() async throws {
        let directory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FaultInjectingPaletteStorage(rootURL: directory)
        let repository = CustomPaletteRepository(storage: storage)
        _ = try await repository.loadAndRepair()
        storage.failNextIndexWrite()

        await #expect(throws: (any Error).self) {
            _ = try await repository.save(
                names: PaletteNames(zh: "事务", ja: ""),
                color: try #require(RGBHex(rawValue: "#112233")),
                avatarWebP: Fixtures.WebP96()
            )
        }
        #expect(try storage.avatarFilenames().isEmpty)
        #expect(try await repository.snapshot().entries.isEmpty)
    }

    @Test func deleteCleanupFailureStillReturnsUndoableCommittedDeletion() async throws {
        let directory = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FaultInjectingPaletteStorage(rootURL: directory)
        let repository = CustomPaletteRepository(storage: storage)
        _ = try await repository.loadAndRepair()
        let entry = try await repository.save(
            names: PaletteNames(zh: "可撤销", ja: ""),
            color: try #require(RGBHex(rawValue: "#445566")),
            avatarWebP: Fixtures.WebP96()
        )
        storage.failNextAvatarRemoval()

        let deletion = try await repository.delete(id: entry.id, expectedRevision: entry.revision)
        #expect(try await repository.snapshot().entries.isEmpty)
        #expect(deletion.entry == entry)
        #expect(deletion.avatarWebP == Fixtures.WebP96())

        // Reconciliation owns orphan cleanup, and the returned payload remains
        // sufficient for a same-session undo even when cleanup failed.
        _ = try await repository.loadAndRepair()
        #expect(try storage.avatarFilenames().isEmpty)
        #expect(try await repository.restore(deletion) == entry)
    }

    @Test func importCleanupFailureKeepsCommittedResultAndRepairsOnReload() async throws {
        let sourceDirectory = try Fixtures.temporaryDirectory()
        let destinationDirectory = try Fixtures.temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let source = CustomPaletteRepository(storage: FileCustomPaletteStorage(rootURL: sourceDirectory))
        _ = try await source.loadAndRepair()
        let initial = try await source.save(
            names: PaletteNames(zh: "事务导入", ja: ""),
            color: try #require(RGBHex(rawValue: "#112233")),
            avatarWebP: Fixtures.WebP96()
        )
        let firstBackup = try await source.exportBackup()
        let updated = try await source.save(
            existingID: initial.id,
            expectedRevision: initial.revision,
            names: initial.names,
            color: initial.color,
            avatarWebP: Fixtures.WebP96(marker: 1)
        )
        let secondBackup = try await source.exportBackup()

        let storage = FaultInjectingPaletteStorage(rootURL: destinationDirectory)
        let destination = CustomPaletteRepository(storage: storage)
        _ = try await destination.loadAndRepair()
        #expect(try await destination.importBackup(firstBackup, conflictPolicy: .overwrite).imported == 1)
        storage.failNextAvatarRemoval()

        let result = try await destination.importBackup(secondBackup, conflictPolicy: .overwrite)
        #expect(result.imported == 1)
        #expect(try await destination.snapshot().entries.first?.avatar.sha256 == updated.avatar.sha256)
        #expect(try storage.avatarFilenames().count == 2)

        _ = try await destination.loadAndRepair()
        #expect(try storage.avatarFilenames() == [updated.avatarFilename])
    }
}

private enum InjectedStorageFailure: Error { case writeIndex, removeAvatar }

private final class FaultInjectingPaletteStorage: CustomPaletteStorage, @unchecked Sendable {
    private let base: FileCustomPaletteStorage
    private let lock = NSLock()
    private var shouldFailIndexWrite = false
    private var shouldFailAvatarRemoval = false

    init(rootURL: URL) { base = FileCustomPaletteStorage(rootURL: rootURL) }

    func failNextIndexWrite() {
        lock.withLock { shouldFailIndexWrite = true }
    }

    func failNextAvatarRemoval() {
        lock.withLock { shouldFailAvatarRemoval = true }
    }

    func readIndex() throws -> Data? { try base.readIndex() }

    func writeIndex(_ data: Data) throws {
        let fail = lock.withLock {
            defer { shouldFailIndexWrite = false }
            return shouldFailIndexWrite
        }
        if fail { throw InjectedStorageFailure.writeIndex }
        try base.writeIndex(data)
    }

    func readAvatar(named filename: String) throws -> Data { try base.readAvatar(named: filename) }
    func writeAvatar(_ data: Data, named filename: String) throws { try base.writeAvatar(data, named: filename) }

    func removeAvatar(named filename: String) throws {
        let fail = lock.withLock {
            defer { shouldFailAvatarRemoval = false }
            return shouldFailAvatarRemoval
        }
        if fail { throw InjectedStorageFailure.removeAvatar }
        try base.removeAvatar(named: filename)
    }

    func avatarFilenames() throws -> Set<String> { try base.avatarFilenames() }
}
