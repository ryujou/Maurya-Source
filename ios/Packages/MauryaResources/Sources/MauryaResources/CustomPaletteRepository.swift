import Foundation
import MauryaShare

public actor CustomPaletteRepository {
    public static let maximumEntries = 50

    private struct Index: Codable, Sendable {
        let schemaVersion: Int
        let entries: [CustomPaletteEntry]
    }

    private let storage: any CustomPaletteStorage
    private let now: @Sendable () -> Date
    private var entries: [CustomPaletteEntry] = []
    private var loaded = false

    public init(
        storage: any CustomPaletteStorage,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.now = now
    }

    @discardableResult
    public func loadAndRepair() throws -> CustomPaletteSnapshot {
        let decoded: [CustomPaletteEntry]
        if let data = try storage.readIndex() {
            guard let index = try? JSONDecoder().decode(Index.self, from: data), index.schemaVersion == 1,
                index.entries.count <= Self.maximumEntries,
                Set(index.entries.map(\.id)).count == index.entries.count
            else {
                throw CustomPaletteError.corruptIndex
            }
            decoded = index.entries.filter { entry in
                guard let bytes = try? storage.readAvatar(named: entry.avatarFilename),
                    (try? AvatarValidator.validate(bytes, expectedSHA256: entry.avatar.sha256)) != nil
                else {
                    return false
                }
                return true
            }
        } else {
            decoded = []
        }
        entries = decoded
        try writeIndex()
        try removeOrphans()
        loaded = true
        return try snapshot()
    }

    public func snapshot() throws -> CustomPaletteSnapshot {
        try requireLoaded()
        let usedBytes = entries.reduce(into: 0) { $0 += $1.avatar.byteCount }
        return CustomPaletteSnapshot(entries: sortedEntries(), usedBytes: usedBytes, limit: Self.maximumEntries)
    }

    public func avatarWebP(id: UUID) throws -> Data {
        try requireLoaded()
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw CustomPaletteError.notFound
        }
        let data = try storage.readAvatar(named: entry.avatarFilename)
        _ = try AvatarValidator.validate(data, expectedSHA256: entry.avatar.sha256)
        return data
    }

    @discardableResult
    public func save(
        existingID: UUID? = nil,
        expectedRevision: Int = 0,
        names: PaletteNames,
        color: RGBHex,
        avatarWebP: Data
    ) throws -> CustomPaletteEntry {
        try requireLoaded()
        let avatar = try AvatarValidator.validate(avatarWebP)
        let old = existingID.flatMap { id in entries.first { $0.id == id } }
        if existingID == nil, entries.count >= Self.maximumEntries {
            throw CustomPaletteError.capacityReached(limit: Self.maximumEntries)
        }
        if existingID != nil, old == nil { throw CustomPaletteError.notFound }
        if let old, old.revision != expectedRevision { throw CustomPaletteError.revisionConflict }
        if let duplicate = entries.first(where: {
            $0.id != existingID && $0.names == names && $0.color == color && $0.avatar.sha256 == avatar.sha256
        }) {
            throw CustomPaletteError.duplicateContent(existingID: duplicate.id)
        }

        let id = existingID ?? UUID()
        let timestamp = Self.timestamp(now())
        let filename = "\(id.uuidString.lowercased())-\(avatar.sha256).webp"
        try storage.writeAvatar(avatarWebP, named: filename)
        let entry = CustomPaletteEntry(
            id: id,
            names: names,
            color: color,
            revision: (old?.revision ?? 0) + 1,
            avatarFilename: filename,
            avatar: avatar,
            createdAt: old?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
        entries.removeAll { $0.id == id }
        entries.append(entry)
        do { try writeIndex() } catch {
            entries.removeAll { $0.id == id }
            if let old { entries.append(old) }
            if old?.avatarFilename != filename { try? storage.removeAvatar(named: filename) }
            throw error
        }
        if let old, old.avatarFilename != filename { try? storage.removeAvatar(named: old.avatarFilename) }
        return entry
    }

    public func delete(id: UUID, expectedRevision: Int) throws -> DeletedPalette {
        try requireLoaded()
        guard let entry = entries.first(where: { $0.id == id }) else { throw CustomPaletteError.notFound }
        guard entry.revision == expectedRevision else { throw CustomPaletteError.revisionConflict }
        let avatar = try storage.readAvatar(named: entry.avatarFilename)
        entries.removeAll { $0.id == id }
        do { try writeIndex() } catch { entries.append(entry); throw error }
        // The index is the source of truth. A failed cleanup must not turn a
        // committed, undoable deletion into an ambiguous thrown failure;
        // `loadAndRepair()` removes the orphan on the next reconciliation.
        try? storage.removeAvatar(named: entry.avatarFilename)
        return DeletedPalette(entry: entry, avatarWebP: avatar)
    }

    public func restore(_ deletion: DeletedPalette) throws -> CustomPaletteEntry {
        try requireLoaded()
        guard entries.count < Self.maximumEntries else {
            throw CustomPaletteError.capacityReached(limit: Self.maximumEntries)
        }
        guard entries.contains(where: { $0.id == deletion.entry.id }) == false else {
            throw CustomPaletteError.revisionConflict
        }
        _ = try AvatarValidator.validate(deletion.avatarWebP, expectedSHA256: deletion.entry.avatar.sha256)
        try storage.writeAvatar(deletion.avatarWebP, named: deletion.entry.avatarFilename)
        entries.append(deletion.entry)
        do { try writeIndex() } catch {
            entries.removeAll { $0.id == deletion.entry.id }
            try? storage.removeAvatar(named: deletion.entry.avatarFilename)
            throw error
        }
        return deletion.entry
    }

    public func exportBackup() throws -> Data {
        try requireLoaded()
        let values = try sortedEntries().map { ($0, try storage.readAvatar(named: $0.avatarFilename)) }
        return try CustomPaletteBackupCodec.encode(entries: values, exportedAt: Self.timestamp(now()))
    }

    public func importBackup(_ data: Data, conflictPolicy: BackupConflictPolicy) throws -> BackupImportResult {
        try requireLoaded()
        let imported = try CustomPaletteBackupCodec.decode(data)
        var next = entries
        var accepted: [CustomPaletteBackupCodec.ValidatedItem] = []
        var skipped = 0
        for item in imported {
            let old = next.first { $0.id == item.id }
            if old != nil, conflictPolicy == .skip { skipped += 1; continue }
            if let duplicate = next.first(where: {
                $0.id != item.id && $0.names == item.names && $0.color == item.color && $0.avatar.sha256 == item.avatar.sha256
            }) {
                _ = duplicate
                skipped += 1
                continue
            }
            guard next.count < Self.maximumEntries || old != nil else {
                throw CustomPaletteError.capacityReached(limit: Self.maximumEntries)
            }
            let filename = "\(item.id.uuidString.lowercased())-\(item.avatar.sha256).webp"
            let entry = CustomPaletteEntry(
                id: item.id,
                names: item.names,
                color: item.color,
                revision: (old?.revision ?? 0) + 1,
                avatarFilename: filename,
                avatar: item.avatar,
                createdAt: old?.createdAt ?? item.createdAt,
                updatedAt: item.updatedAt
            )
            next.removeAll { $0.id == item.id }
            next.append(entry)
            accepted.append(item)
        }
        let existingFilenames = try storage.avatarFilenames()
        var newlyWritten: [String] = []
        do {
            for item in accepted {
                let filename = "\(item.id.uuidString.lowercased())-\(item.avatar.sha256).webp"
                try storage.writeAvatar(item.avatarWebP, named: filename)
                if existingFilenames.contains(filename) == false { newlyWritten.append(filename) }
            }
        } catch {
            for filename in newlyWritten { try? storage.removeAvatar(named: filename) }
            throw error
        }
        let previous = entries
        entries = next
        do { try writeIndex() } catch {
            entries = previous
            for filename in newlyWritten { try? storage.removeAvatar(named: filename) }
            throw error
        }
        // The index is the committed source of truth. Cleanup failure after a
        // successful index write must not report the import as failed while
        // the imported entries are already visible. `loadAndRepair()` retries
        // orphan cleanup on the next reconciliation.
        try? removeOrphans()
        return BackupImportResult(imported: accepted.count, skipped: skipped)
    }

    public func importShare(
        names: ShareDisplayName,
        payload: PaletteSharePayload
    ) throws -> CustomPaletteEntry {
        _ = try payload.validatedAvatarMetadata()
        guard let color = RGBHex(rawValue: payload.hex) else { throw CustomPaletteError.invalidColor }
        return try save(
            names: PaletteNames(zh: names.zh, ja: names.ja),
            color: color,
            avatarWebP: payload.avatarWebP
        )
    }

    private func sortedEntries() -> [CustomPaletteEntry] {
        entries.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    private func writeIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try storage.writeIndex(encoder.encode(Index(schemaVersion: 1, entries: entries)))
    }

    private func removeOrphans() throws {
        let referenced = Set(entries.map(\.avatarFilename))
        for filename in try storage.avatarFilenames().subtracting(referenced) {
            try storage.removeAvatar(named: filename)
        }
    }

    private func requireLoaded() throws {
        if loaded == false { throw CustomPaletteError.corruptIndex }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
