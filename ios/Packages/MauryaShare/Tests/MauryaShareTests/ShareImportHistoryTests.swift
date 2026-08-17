import Foundation
import Testing

@testable import MauryaShare

struct ShareImportHistoryTests {
    @Test func recordsAreAtomicDeduplicatedAndNewestFirst() async throws {
        let file = temporaryFile()
        let history = ShareImportHistory(fileURL: file)
        try await history.recordImport(token: "K8F3Q7D2PX", localID: "first", importedAt: Date(timeIntervalSince1970: 1))
        try await history.recordImport(token: "J8F3Q7D2PX", localID: "second", importedAt: Date(timeIntervalSince1970: 2))
        try await history.recordImport(token: "K8F3Q7D2PX", localID: "replacement", importedAt: Date(timeIntervalSince1970: 3))

        let records = try await history.records()
        #expect(records.count == 2)
        #expect(records[0].localID == "replacement")
        #expect(records[1].localID == "second")
        #expect(try await history.wasImported("K8F3Q-7D2PX"))

        let reloaded = ShareImportHistory(fileURL: file)
        #expect(try await reloaded.records() == records)
    }

    @Test func historyIsCappedAtAndroidLimit() async throws {
        let history = ShareImportHistory(fileURL: temporaryFile())
        for index in 0..<300 {
            let token = base58Token(index)
            try await history.recordImport(token: token, localID: "id-\(index)")
        }
        let records = try await history.records()
        #expect(records.count == ShareImportHistory.maximumRecords)
        #expect(records.first?.localID == "id-299")
        #expect(records.last?.localID == "id-44")
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MauryaShareTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private func base58Token(_ value: Int) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var number = value
        var suffix = ""
        repeat {
            suffix.append(alphabet[number % alphabet.count])
            number /= alphabet.count
        } while number > 0
        return String(repeating: "1", count: 10 - suffix.count) + String(suffix.reversed())
    }
}
