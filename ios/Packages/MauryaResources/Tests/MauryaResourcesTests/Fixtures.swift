import Foundation

enum Fixtures {
    static func WebP96(marker: UInt8 = 0) -> Data {
        var bytes = [UInt8](repeating: 0, count: 30)
        bytes.replaceSubrange(0..<4, with: Array("RIFF".utf8))
        bytes[4] = 22
        bytes.replaceSubrange(8..<12, with: Array("WEBP".utf8))
        bytes.replaceSubrange(12..<16, with: Array("VP8X".utf8))
        bytes[16] = 10
        bytes[20] = marker
        bytes[24] = 95
        bytes[27] = 95
        return Data(bytes)
    }

    static func temporaryDirectory() throws -> URL {
        let URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MauryaResourcesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
        return URL
    }
}
