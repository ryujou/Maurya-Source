import CryptoKit
import Foundation
import Testing

@testable import MauryaOTA

@Suite("OTA artifact Range cache", .serialized)
struct OTAArtifactDownloadTests {
    @Test func resumesPersistedPartialWithIfRangeAndBoundedChunks() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        try seedPartial(Data([0, 1, 2]), entityTag: "\"v1\"", url: url, directory: directory)
        let remaining = Data(repeating: 7, count: 300_000)
        ScriptedOTAURLProtocol.install { request in
            let range = try #require(request.value(forHTTPHeaderField: "Range"))
            let start = try #require(UInt64(range.dropFirst(6).split(separator: "-")[0]))
            let end = min(UInt64(remaining.count + 2), start + 256 * 1_024 - 1)
            let body = remaining.subdata(in: Int(start - 3)..<Int(end - 2))
            return try response(
                request,
                status: 206,
                headers: ["Content-Range": "bytes \(start)-\(end)/300003", "ETag": "\"v1\""],
                body: body
            )
        }
        let client = try makeClient(directory: directory)
        let artifact = try await client.fetchArtifact(from: url, maximumBytes: 400_000)

        #expect(artifact.bytes == Data([0, 1, 2]) + remaining)
        #expect(artifact.entityTag == "\"v1\"")
        let requests = ScriptedOTAURLProtocol.requests()
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Range") == "bytes=3-262146")
        #expect(requests[0].value(forHTTPHeaderField: "If-Range") == "\"v1\"")
    }

    @Test func changedETagDiscardsPartialAndRestartsCleanly() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        try seedPartial(Data([9, 9]), entityTag: "\"old\"", url: url, directory: directory)
        let expected = Data([1, 2, 3, 4])
        ScriptedOTAURLProtocol.install { request in
            if request.value(forHTTPHeaderField: "Range")?.hasPrefix("bytes=2-") == true {
                return try response(
                    request,
                    status: 206,
                    headers: ["Content-Range": "bytes 2-3/4", "ETag": "\"new\""],
                    body: Data([3, 4])
                )
            }
            return try response(request, status: 200, headers: ["ETag": "\"new\""], body: expected)
        }
        let client = try makeClient(directory: directory)

        #expect(try await client.fetchArtifact(from: url, maximumBytes: 10).bytes == expected)
        let requests = ScriptedOTAURLProtocol.requests()
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "Range") == "bytes=0-9")
    }

    @Test func rangeNotSatisfiableRestartsOnlyOnce() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        try seedPartial(Data([8]), entityTag: "\"v1\"", url: url, directory: directory)
        let expected = Data([5, 6, 7])
        ScriptedOTAURLProtocol.install { request in
            if request.value(forHTTPHeaderField: "Range")?.hasPrefix("bytes=1-") == true {
                return try response(request, status: 416, body: Data())
            }
            return try response(request, status: 200, headers: ["ETag": "\"v2\""], body: expected)
        }
        let client = try makeClient(directory: directory)
        #expect(try await client.fetchArtifact(from: url, maximumBytes: 10).bytes == expected)
        #expect(ScriptedOTAURLProtocol.requests().count == 2)
    }

    @Test func missingValidatorDiscardsPersistedPartialBeforeNetworkUse() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        let key = cacheKey(url)
        try Data([9, 9, 9]).write(to: directory.appendingPathComponent("\(key).part"))
        let expected = Data([1, 2, 3])
        ScriptedOTAURLProtocol.install { request in
            try response(request, status: 200, headers: ["ETag": "\"fresh\""], body: expected)
        }

        let artifact = try await makeClient(directory: directory)
            .fetchArtifact(from: url, maximumBytes: 10)
        #expect(artifact.bytes == expected)
        #expect(ScriptedOTAURLProtocol.requests().first?.value(forHTTPHeaderField: "Range") == "bytes=0-9")
    }

    @Test func insufficientDiskCapacityFailsBeforeAnyRequest() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        ScriptedOTAURLProtocol.install { request in
            try response(request, status: 200, body: Data([1]))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedOTAURLProtocol.self]
        let client = try URLSessionOTAClient(
            baseURL: #require(URL(string: "https://updates.example/stable/")),
            allowedHosts: ["updates.example"],
            keyID: "test",
            session: URLSession(configuration: configuration),
            artifactCacheDirectory: directory,
            availableDiskCapacity: { _ in 0 }
        )

        await #expect(throws: OTAFailure.storage("Insufficient disk space for OTA artifact")) {
            try await client.fetchArtifact(from: url, maximumBytes: 10)
        }
        #expect(ScriptedOTAURLProtocol.requests().isEmpty)
    }

    @Test func responseBodyIsStoppedAtConfiguredMaximum() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        ScriptedOTAURLProtocol.install { request in
            try response(request, status: 200, body: Data(repeating: 1, count: 11))
        }

        await #expect(throws: OTAFailure.artifactTooLarge(11)) {
            try await makeClient(directory: directory).fetchArtifact(from: url, maximumBytes: 10)
        }
    }

    @Test func completedRangeChunkSurvivesNetworkFailureAndResumes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://updates.example/firmware.bin"))
        let total = 300_000
        let counter = LockedCounter()
        ScriptedOTAURLProtocol.install { request in
            if counter.incrementAndGet() == 1 {
                return try response(
                    request,
                    status: 206,
                    headers: [
                        "Content-Range": "bytes 0-262143/\(total)",
                        "ETag": "\"stable\"",
                    ],
                    body: Data(repeating: 4, count: 262_144)
                )
            }
            throw URLError(.networkConnectionLost)
        }
        await #expect(throws: OTAFailure.disconnected) {
            try await makeClient(directory: directory).fetchArtifact(
                from: url,
                maximumBytes: UInt64(total)
            )
        }

        ScriptedOTAURLProtocol.install { request in
            let range = request.value(forHTTPHeaderField: "Range")
            #expect(range == "bytes=262144-299999")
            #expect(request.value(forHTTPHeaderField: "If-Range") == "\"stable\"")
            return try response(
                request,
                status: 206,
                headers: [
                    "Content-Range": "bytes 262144-299999/\(total)",
                    "ETag": "\"stable\"",
                ],
                body: Data(repeating: 4, count: total - 262_144)
            )
        }
        let artifact = try await makeClient(directory: directory).fetchArtifact(
            from: url,
            maximumBytes: UInt64(total)
        )
        #expect(artifact.bytes == Data(repeating: 4, count: total))
    }

    private func makeClient(directory: URL) throws -> URLSessionOTAClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedOTAURLProtocol.self]
        return try URLSessionOTAClient(
            baseURL: #require(URL(string: "https://updates.example/stable/")),
            allowedHosts: ["updates.example"],
            keyID: "test",
            session: URLSession(configuration: configuration),
            artifactCacheDirectory: directory
        )
    }
}

private final class ScriptedOTAURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    static func install(_ value: @escaping Handler) {
        lock.withLock {
            handler = value; captured = []
        }
    }

    static func requests() -> [URLRequest] { lock.withLock { captured } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result: Result<(HTTPURLResponse, Data), any Error> = Self.lock.withLock {
            Self.captured.append(request)
            guard let handler = Self.handler else { return .failure(URLError(.badServerResponse)) }
            return Result { try handler(request) }
        }
        do {
            let (response, data) = try result.get()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func incrementAndGet() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private func response(
    _ request: URLRequest,
    status: Int,
    headers: [String: String] = [:],
    body: Data
) throws -> (HTTPURLResponse, Data) {
    let URL = try #require(request.url)
    return (
        try #require(
            HTTPURLResponse(
                url: URL,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )), body
    )
}

private func temporaryDirectory() throws -> URL {
    let URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("MauryaOTARangeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
    return URL
}

private func seedPartial(_ data: Data, entityTag: String, url: URL, directory: URL) throws {
    let key = cacheKey(url)
    try data.write(to: directory.appendingPathComponent("\(key).part"))
    try Data(entityTag.utf8).write(to: directory.appendingPathComponent("\(key).etag"))
}

private func cacheKey(_ url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8))
        .map { String(format: "%02x", $0) }.joined()
}
