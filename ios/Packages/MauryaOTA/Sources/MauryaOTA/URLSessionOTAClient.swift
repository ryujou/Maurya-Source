import CryptoKit
import Foundation

public actor URLSessionOTAClient: OTAHTTPSClient {
    private let baseURL: URL
    private let allowedHosts: Set<String>
    private let keyID: String
    private let session: URLSession
    private let artifactCacheDirectory: URL
    private let availableDiskCapacity: @Sendable (URL) throws -> Int64?
    private let rangeChunkBytes = 256 * 1_024

    public init(
        baseURL: URL,
        allowedHosts: Set<String>,
        keyID: String,
        session: URLSession,
        artifactCacheDirectory: URL? = nil,
        availableDiskCapacity: @escaping @Sendable (URL) throws -> Int64? = { URL in
            try URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
        }
    ) throws {
        try Self.validate(url: baseURL, allowedHosts: allowedHosts)
        self.baseURL = baseURL
        self.allowedHosts = allowedHosts
        self.keyID = keyID
        self.session = session
        self.artifactCacheDirectory =
            artifactCacheDirectory
            ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MauryaOTA", isDirectory: true)
        self.availableDiskCapacity = availableDiskCapacity
    }

    public func fetchSignedManifest(channel: String, variant: String) async throws -> SignedOTAManifest {
        guard Self.isSafePathComponent(channel), Self.isSafePathComponent(variant) else {
            throw OTAFailure.invalidManifest("Invalid OTA channel or variant")
        }
        let directory =
            baseURL
            .appending(path: channel, directoryHint: .isDirectory)
            .appending(path: variant, directoryHint: .isDirectory)
        let manifestURL = directory.appending(path: "manifest.json")
        let signatureURL = directory.appending(path: "manifest.sig")
        async let manifest = fetchSmall(url: manifestURL, maximumBytes: 128 * 1024, noCache: true)
        async let signature = fetchSmall(url: signatureURL, maximumBytes: 16 * 1024, noCache: true)
        return try await SignedOTAManifest(
            manifestBytes: manifest.data,
            detachedSignature: signature.data,
            keyID: keyID
        )
    }

    public func fetchArtifact(from url: URL, maximumBytes: UInt64) async throws -> OTAArtifact {
        try Self.validate(url: url, allowedHosts: allowedHosts)
        guard maximumBytes > 0, maximumBytes <= UInt64(Int.max) else {
            throw OTAFailure.artifactTooLarge(maximumBytes)
        }
        let files = try prepareArtifactFiles(for: url)
        try discardUnsafePartial(files: files, maximumBytes: maximumBytes)
        var didRestartAfterRangeFailure = false
        var requestsRemaining = Int((maximumBytes + UInt64(rangeChunkBytes) - 1) / UInt64(rangeChunkBytes)) + 2

        while requestsRemaining > 0 {
            requestsRemaining -= 1
            try Task.checkCancellation()
            let offset = try fileSize(files.partial)
            try requireDiskCapacity(additionalBytes: maximumBytes > offset ? maximumBytes - offset : 0)
            let upperBound = min(maximumBytes - 1, offset + UInt64(rangeChunkBytes) - 1)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("bytes=\(offset)-\(upperBound)", forHTTPHeaderField: "Range")
            let previousETag = try readETag(files.entityTag)
            if offset > 0, let previousETag {
                request.setValue(previousETag, forHTTPHeaderField: "If-Range")
            }

            let (data, rawResponse) = try await performBounded(
                request,
                maximumBytes: maximumBytes
            )
            guard let response = rawResponse as? HTTPURLResponse, let finalURL = response.url else {
                throw OTAFailure.network("Non-HTTP artifact response")
            }
            try Self.validate(url: finalURL, allowedHosts: allowedHosts)
            let responseETag = response.value(forHTTPHeaderField: "ETag")

            switch response.statusCode {
            case 200:
                guard UInt64(data.count) <= maximumBytes else {
                    throw OTAFailure.artifactTooLarge(UInt64(data.count))
                }
                try data.write(to: files.partial, options: .atomic)
                try writeETag(responseETag, to: files.entityTag)
                return try finishArtifact(files: files, sourceURL: url, entityTag: responseETag)

            case 206:
                guard let range = Self.parseContentRange(response.value(forHTTPHeaderField: "Content-Range")),
                    range.start == offset,
                    range.end >= range.start,
                    range.total <= maximumBytes,
                    UInt64(data.count) == range.end - range.start + 1
                else {
                    throw OTAFailure.network("Invalid HTTP Content-Range")
                }
                if offset > 0, previousETag != responseETag {
                    guard didRestartAfterRangeFailure == false else {
                        throw OTAFailure.network("Artifact ETag changed repeatedly")
                    }
                    try resetPartial(files)
                    didRestartAfterRangeFailure = true
                    continue
                }
                try append(data, to: files.partial)
                try writeETag(responseETag, to: files.entityTag)
                if range.end + 1 == range.total {
                    return try finishArtifact(files: files, sourceURL: url, entityTag: responseETag)
                }

            case 416:
                guard didRestartAfterRangeFailure == false else {
                    throw OTAFailure.network("HTTP 416 after clean restart")
                }
                try resetPartial(files)
                didRestartAfterRangeFailure = true

            default:
                throw OTAFailure.network("HTTP \(response.statusCode)")
            }
        }
        throw OTAFailure.network("Artifact Range download exceeded its request bound")
    }

    private func fetchSmall(
        url: URL,
        maximumBytes: UInt64,
        noCache: Bool
    ) async throws -> (data: Data, entityTag: String?) {
        try Self.validate(url: url, allowedHosts: allowedHosts)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if noCache { request.setValue("no-cache", forHTTPHeaderField: "Cache-Control") }
        do {
            let (data, response) = try await performBounded(request, maximumBytes: maximumBytes)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw OTAFailure.network("Non-HTTP response")
            }
            guard let finalURL = response.url else {
                throw OTAFailure.network("HTTP response has no final URL")
            }
            // URLSession follows redirects by default. Revalidate the final URL
            // so a trusted endpoint cannot redirect to plain HTTP, a
            // credential-bearing URL, or another host.
            try Self.validate(url: finalURL, allowedHosts: allowedHosts)
            guard response.statusCode == 200 else {
                throw OTAFailure.network("HTTP \(response.statusCode)")
            }
            if response.expectedContentLength > 0,
                UInt64(response.expectedContentLength) > maximumBytes
            {
                throw OTAFailure.artifactTooLarge(UInt64(response.expectedContentLength))
            }
            guard UInt64(data.count) <= maximumBytes else {
                throw OTAFailure.artifactTooLarge(UInt64(data.count))
            }
            return (data, response.value(forHTTPHeaderField: "ETag"))
        } catch is CancellationError {
            throw OTAFailure.cancelled
        } catch let failure as OTAFailure {
            throw failure
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw OTAFailure.cancelled
            case .timedOut: throw OTAFailure.responseTimedOut
            case .networkConnectionLost, .notConnectedToInternet:
                throw OTAFailure.disconnected
            default: throw OTAFailure.network(String(describing: error))
            }
        } catch {
            throw OTAFailure.network(String(describing: error))
        }
    }

    private func performBounded(
        _ request: URLRequest,
        maximumBytes: UInt64
    ) async throws -> (Data, URLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if response.expectedContentLength > 0,
                UInt64(response.expectedContentLength) > maximumBytes
            {
                throw OTAFailure.artifactTooLarge(UInt64(response.expectedContentLength))
            }
            var data = Data()
            data.reserveCapacity(Int(min(maximumBytes, UInt64(Int.max))))
            for try await byte in bytes {
                guard UInt64(data.count) < maximumBytes else {
                    throw OTAFailure.artifactTooLarge(UInt64(data.count) + 1)
                }
                data.append(byte)
            }
            return (data, response)
        } catch is CancellationError { throw OTAFailure.cancelled } catch let failure as OTAFailure { throw failure } catch let error
            as URLError
        {
            switch error.code {
            case .cancelled: throw OTAFailure.cancelled
            case .timedOut: throw OTAFailure.responseTimedOut
            case .networkConnectionLost, .notConnectedToInternet: throw OTAFailure.disconnected
            default: throw OTAFailure.network(String(describing: error))
            }
        }
    }

    private typealias ArtifactFiles = (partial: URL, final: URL, entityTag: URL)

    private func prepareArtifactFiles(for url: URL) throws -> ArtifactFiles {
        try FileManager.default.createDirectory(at: artifactCacheDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = artifactCacheDirectory
        try directory.setResourceValues(values)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (
            artifactCacheDirectory.appendingPathComponent("\(key).part"),
            artifactCacheDirectory.appendingPathComponent("\(key).bin"),
            artifactCacheDirectory.appendingPathComponent("\(key).etag")
        )
    }

    private func discardUnsafePartial(files: ArtifactFiles, maximumBytes: UInt64) throws {
        let size = try fileSize(files.partial)
        let hasResumeValidator = try readETag(files.entityTag) != nil
        if size > maximumBytes || (size > 0 && hasResumeValidator == false) {
            try resetPartial(files)
        }
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.seekToEnd()
    }

    private func requireDiskCapacity(additionalBytes: UInt64) throws {
        if let available = try availableDiskCapacity(artifactCacheDirectory),
            UInt64(max(0, available)) < additionalBytes
        {
            throw OTAFailure.storage("Insufficient disk space for OTA artifact")
        }
    }

    private func append(_ data: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) == false {
            try Data().write(to: url, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func finishArtifact(
        files: ArtifactFiles,
        sourceURL: URL,
        entityTag: String?
    ) throws -> OTAArtifact {
        let manager = FileManager.default
        if manager.fileExists(atPath: files.final.path) {
            _ = try manager.replaceItemAt(files.final, withItemAt: files.partial)
        } else {
            try manager.moveItem(at: files.partial, to: files.final)
        }
        let bytes = try Data(contentsOf: files.final, options: [.mappedIfSafe])
        return OTAArtifact(bytes: bytes, sourceURL: sourceURL, entityTag: entityTag)
    }

    private func resetPartial(_ files: ArtifactFiles) throws {
        let manager = FileManager.default
        for url in [files.partial, files.entityTag] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    private func readETag(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try String(contentsOf: url, encoding: .utf8)
        return value.isEmpty ? nil : value
    }

    private func writeETag(_ value: String?, to url: URL) throws {
        if let value, value.isEmpty == false {
            try Data(value.utf8).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func parseContentRange(_ value: String?) -> (start: UInt64, end: UInt64, total: UInt64)? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let components = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, let total = UInt64(components[1]) else { return nil }
        let bounds = components[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = UInt64(bounds[0]), let end = UInt64(bounds[1]),
            start <= end, end < total
        else { return nil }
        return (start, end, total)
    }

    static func validate(url: URL, allowedHosts: Set<String>) throws {
        guard url.scheme?.lowercased() == "https" else { throw OTAFailure.insecureURL }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw OTAFailure.untrustedHost(url.host ?? "")
        }
        guard url.user == nil, url.password == nil else {
            throw OTAFailure.invalidManifest("Credentials are forbidden in OTA URLs")
        }
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        value.isEmpty == false && value != "." && value != ".." && value.contains("/") == false && value.contains("\\") == false
    }
}
