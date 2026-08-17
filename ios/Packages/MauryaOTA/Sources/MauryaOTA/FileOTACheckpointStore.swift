import Foundation

public actor FileOTACheckpointStore: OTACheckpointStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        self.directory = directory
    }

    public func load(deviceID: String) throws -> OTACheckpoint? {
        let url = fileURL(deviceID: deviceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(OTACheckpoint.self, from: Data(contentsOf: url))
        } catch {
            throw OTAFailure.storage("Unable to decode OTA checkpoint")
        }
    }

    public func save(_ checkpoint: OTACheckpoint) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let data = try encoder.encode(checkpoint)
            try data.write(to: fileURL(deviceID: checkpoint.deviceID), options: .atomic)
        } catch {
            throw OTAFailure.storage("Unable to persist OTA checkpoint")
        }
    }

    public func remove(deviceID: String) throws {
        let url = fileURL(deviceID: deviceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch { throw OTAFailure.storage("Unable to remove OTA checkpoint") }
    }

    private func fileURL(deviceID: String) -> URL {
        let safeName = Data(deviceID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appending(path: "\(safeName).json")
    }
}
