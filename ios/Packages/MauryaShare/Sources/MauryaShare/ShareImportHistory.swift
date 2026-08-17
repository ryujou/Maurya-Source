import Foundation

public struct ShareImportRecord: Sendable, Equatable, Codable {
    public let tokenHash: String
    public let localID: String
    public let importedAt: Date

    public init(tokenHash: String, localID: String, importedAt: Date) {
        self.tokenHash = tokenHash
        self.localID = localID
        self.importedAt = importedAt
    }
}

public enum ShareImportHistoryError: Error, Sendable, Equatable {
    case invalidRecord
    case invalidStore
    case persistenceFailed
}

/// Serializes history access and only publishes a mutation after the complete
/// replacement file has been written atomically.
public actor ShareImportHistory {
    public static let maximumRecords = 256
    private static let maximumFileBytes = 256 * 1_024

    private let fileURL: URL
    private var cachedRecords: [ShareImportRecord]?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupportFile(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ShareImportHistoryError.persistenceFailed
        }
        return directory.appendingPathComponent("Maurya", isDirectory: true)
            .appendingPathComponent("share-import-history.json", isDirectory: false)
    }

    public func records() throws -> [ShareImportRecord] {
        try loadIfNeeded()
    }

    public func wasImported(_ rawToken: String) throws -> Bool {
        let hash = try tokenHash(rawToken)
        return try loadIfNeeded().contains { $0.tokenHash == hash }
    }

    @discardableResult
    public func recordImport(
        token rawToken: String,
        localID: String,
        importedAt: Date = Date()
    ) throws -> ShareImportRecord {
        guard localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            localID.utf8.count <= 1_024
        else {
            throw ShareImportHistoryError.invalidRecord
        }
        let record = ShareImportRecord(
            tokenHash: try tokenHash(rawToken),
            localID: localID,
            importedAt: importedAt
        )
        let existing = try loadIfNeeded()
        let next = Array(([record] + existing.filter { $0.tokenHash != record.tokenHash }).prefix(Self.maximumRecords))
        try persist(next)
        cachedRecords = next
        return record
    }

    public func removeAll() throws {
        try persist([])
        cachedRecords = []
    }

    private func loadIfNeeded() throws -> [ShareImportRecord] {
        if let cachedRecords { return cachedRecords }
        let records: [ShareImportRecord]
        if FileManager.default.fileExists(atPath: fileURL.path) == false {
            records = []
        } else {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                guard data.count <= Self.maximumFileBytes else { throw ShareImportHistoryError.invalidStore }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                records = try decoder.decode([ShareImportRecord].self, from: data)
                guard records.count <= Self.maximumRecords,
                    Set(records.map(\.tokenHash)).count == records.count,
                    records.allSatisfy({ isValid($0) })
                else {
                    throw ShareImportHistoryError.invalidStore
                }
            } catch let error as ShareImportHistoryError {
                throw error
            } catch {
                throw ShareImportHistoryError.invalidStore
            }
        }
        cachedRecords = records
        return records
    }

    private func persist(_ records: [ShareImportRecord]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(records)
            guard data.count <= Self.maximumFileBytes else { throw ShareImportHistoryError.persistenceFailed }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch let error as ShareImportHistoryError {
            throw error
        } catch {
            throw ShareImportHistoryError.persistenceFailed
        }
    }

    private func tokenHash(_ rawToken: String) throws -> String {
        let token = try ShareToken.parse(rawToken)
        return ShareEnvelopeCodec.sha256(Data(token.utf8))
    }

    private func isValid(_ record: ShareImportRecord) -> Bool {
        record.tokenHash.utf8.count == 64 && record.tokenHash.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
            && record.localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && record.localID.utf8.count <= 1_024
    }
}
