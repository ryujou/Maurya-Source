import Foundation

public actor EditorAutosaveStore {
    public let fileURL: URL
    public let maximumBytes: Int

    public init(fileURL: URL, maximumBytes: Int = 1_000_000) {
        self.fileURL = fileURL
        self.maximumBytes = maximumBytes
    }

    public func save(_ document: String) throws {
        let data = Data(document.utf8)
        guard data.count <= maximumBytes else { throw EditorBridgeError.invalidPayload }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
            // File protection is an iOS-family data-at-rest policy. Requesting it
            // for a macOS temporary directory can make the atomic rename fail.
            let writeOptions: Data.WritingOptions = [.atomic]
        #endif
        try data.write(to: fileURL, options: writeOptions)
    }

    public func restore() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= maximumBytes, let value = String(data: data, encoding: .utf8) else { throw EditorBridgeError.invalidPayload }
        return value
    }
}
