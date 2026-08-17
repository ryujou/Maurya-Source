import Foundation

public protocol CustomPaletteStorage: Sendable {
    func readIndex() throws -> Data?
    func writeIndex(_ data: Data) throws
    func readAvatar(named filename: String) throws -> Data
    func writeAvatar(_ data: Data, named filename: String) throws
    func removeAvatar(named filename: String) throws
    func avatarFilenames() throws -> Set<String>
}

public struct FileCustomPaletteStorage: CustomPaletteStorage, Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func readIndex() throws -> Data? {
        let URL = rootURL.appendingPathComponent("index.json", isDirectory: false)
        guard FileManager().fileExists(atPath: URL.path) else { return nil }
        return try Data(contentsOf: URL)
    }

    public func writeIndex(_ data: Data) throws {
        try prepareDirectories()
        let URL = rootURL.appendingPathComponent("index.json")
        try data.write(to: URL, options: [.atomic])
        try protect(URL)
    }

    public func readAvatar(named filename: String) throws -> Data {
        try Data(contentsOf: avatarURL(filename))
    }

    public func writeAvatar(_ data: Data, named filename: String) throws {
        try prepareDirectories()
        let URL = try avatarURL(filename)
        try data.write(to: URL, options: [.atomic])
        try protect(URL)
    }

    public func removeAvatar(named filename: String) throws {
        let fileManager = FileManager()
        let URL = try avatarURL(filename)
        if fileManager.fileExists(atPath: URL.path) { try fileManager.removeItem(at: URL) }
    }

    public func avatarFilenames() throws -> Set<String> {
        let directory = rootURL.appendingPathComponent("avatars", isDirectory: true)
        guard FileManager().fileExists(atPath: directory.path) else { return [] }
        return Set(try FileManager().contentsOfDirectory(atPath: directory.path))
    }

    private func prepareDirectories() throws {
        let fileManager = FileManager()
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent("avatars", isDirectory: true),
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootURL
        try mutableRoot.setResourceValues(values)
        #if os(iOS) || os(tvOS) || os(watchOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: rootURL.path
            )
        #endif
    }

    private func protect(_ URL: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
            try FileManager().setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: URL.path
            )
        #endif
    }

    private func avatarURL(_ filename: String) throws -> URL {
        guard filename.range(of: "^[0-9a-f-]+-[0-9a-f]{64}\\.webp$", options: .regularExpression) != nil,
            filename.contains("..") == false
        else { throw CustomPaletteError.invalidIdentifier }
        return rootURL.appendingPathComponent("avatars", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }
}
