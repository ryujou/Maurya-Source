import CryptoKit
import Foundation

public struct EditorBundleManifest: Sendable, Codable, Equatable {
    public struct FileRecord: Sendable, Codable, Equatable {
        public let path: String
        public let size: Int
        public let sha256: String
        public let mediaType: String
    }

    public let formatVersion: Int
    public let editorVersion: String
    public let sourcePackage: String
    public let bundleSHA256: String
    public let generatedAt: String
    public let files: [FileRecord]
}

public struct VerifiedEditorBundle: Sendable {
    public let rootURL: URL
    public let manifest: EditorBundleManifest
    let recordsByPath: [String: EditorBundleManifest.FileRecord]

    public var editorVersion: String { manifest.editorVersion }
    public var bundleSHA256: String { manifest.bundleSHA256 }

    public func record(for path: String) -> EditorBundleManifest.FileRecord? { recordsByPath[path] }
}

public enum EditorBundleError: Error, Sendable, Equatable {
    case missingResource
    case malformedManifest
    case unsupportedManifest
    case unsafePath(String)
    case missingFile(String)
    case sizeMismatch(String)
    case hashMismatch(String)
}

public enum EditorBundleVerifier {
    public static func verify() throws -> VerifiedEditorBundle { try verify(bundle: .module) }

    public static func verify(bundle: Bundle) throws -> VerifiedEditorBundle {
        guard let rootURL = bundle.url(forResource: "EditorBundle", withExtension: nil),
            let manifestURL = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "EditorBundle")
        else {
            throw EditorBundleError.missingResource
        }
        let manifest: EditorBundleManifest
        do { manifest = try JSONDecoder().decode(EditorBundleManifest.self, from: Data(contentsOf: manifestURL)) } catch {
            throw EditorBundleError.malformedManifest
        }
        guard manifest.formatVersion == 1 else { throw EditorBundleError.unsupportedManifest }
        var records: [String: EditorBundleManifest.FileRecord] = [:]
        for record in manifest.files {
            guard isSafeRelativePath(record.path), records[record.path] == nil else { throw EditorBundleError.unsafePath(record.path) }
            let fileURL = rootURL.appending(path: record.path)
            guard FileManager.default.isReadableFile(atPath: fileURL.path) else { throw EditorBundleError.missingFile(record.path) }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard data.count == record.size else { throw EditorBundleError.sizeMismatch(record.path) }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == record.sha256.lowercased() else { throw EditorBundleError.hashMismatch(record.path) }
            records[record.path] = record
        }
        let canonical = manifest.files.sorted { $0.path < $1.path }.map {
            "\($0.path)\u{0}\($0.size)\u{0}\($0.sha256.lowercased())"
        }.joined(separator: "\n")
        let bundleHash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        guard bundleHash == manifest.bundleSHA256.lowercased() else { throw EditorBundleError.hashMismatch("manifest") }
        guard records["index.html"] != nil, records["script.html"] != nil else { throw EditorBundleError.missingResource }
        return VerifiedEditorBundle(rootURL: rootURL, manifest: manifest, recordsByPath: records)
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && path.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." && !$0.isEmpty }
    }
}
