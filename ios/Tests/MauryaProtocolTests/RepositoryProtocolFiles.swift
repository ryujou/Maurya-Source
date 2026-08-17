import Foundation

enum RepositoryProtocolFiles {
    static func goldenVectors() throws -> GoldenVectorDocument {
        try JSONDecoder().decode(
            GoldenVectorDocument.self,
            from: Data(contentsOf: protocolDirectory.appending(path: "golden-vectors.json"))
        )
    }

    static func schemaJSONObject() throws -> [String: Any] {
        let data = try Data(contentsOf: protocolDirectory.appending(path: "maurya-protocol.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private static var protocolDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "protocol", directoryHint: .isDirectory)
    }
}
