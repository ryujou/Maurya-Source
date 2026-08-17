import Foundation
import Testing

@testable import MauryaShare

extension Tag {
    @Tag static var networking: Self
}

@Suite(.serialized)
struct ShareAPIClientTests {
    @Test(.tags(.networking))
    func createUsesContractHeadersAndNeverRetriesPOST() async throws {
        let transport = FakeShareTransport(results: [
            .success(
                response(
                    url: "https://xtbang.top/maurya/api/share/v1/shares",
                    status: 201,
                    contentType: "application/json",
                    body: Data(
                        #"{"blobSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","createdAt":"2026-08-11T03:31:09Z","expiresAt":"2026-08-15T00:00:00Z","expiresInSeconds":604800,"kind":"effect","moderationVersion":"v1","schema":1,"shareUrl":"https://xtbang.top/maurya/s/K8F3Q7D2PX","token":"K8F3Q7D2PX"}"#
                            .utf8)
                ))
        ])
        let client = try makeClient(transport)
        let envelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "安全", ja: ""),
            sourceKind: .script,
            source: "effect \"safe\" { wait(1s); }"
        )
        let created = try await client.create(
            envelope,
            idempotencyKey: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        )
        #expect(created.token == "K8F3Q7D2PX")
        let requests = await transport.requests
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == ShareAPIClient.mediaType)
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "00000000-0000-0000-0000-000000000001")
        #expect(request.httpBody?.isEmpty == false)
        #expect(requests.count == 1)
    }

    @Test(.tags(.networking))
    func fetchPreviewRetriesGETAndValidatesBlob() async throws {
        let envelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "安全", ja: ""),
            sourceKind: .script,
            source: "effect \"safe\" { wait(1s); }"
        )
        let dated = ShareEnvelope(
            kind: envelope.kind,
            displayName: envelope.displayName,
            payload: envelope.payload,
            contentHash: envelope.contentHash,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let blob = try Gzip.compress(
            ShareEnvelopeCodec.canonicalEnvelope(dated, includeCreatedAt: true),
            maximumOutput: ShareEnvelopeCodec.maximumCompressedBytes
        )
        let hash = ShareEnvelopeCodec.sha256(blob)
        let metadata = Data(
            """
            {"kind":"effect","createdAt":"2023-11-14T22:13:20Z","expiresAt":"2023-11-21T22:13:20Z","expiresInSeconds":604800,"compressedBytes":\(blob.count),"blobSha256":"\(hash)"}
            """.utf8)
        let transport = FakeShareTransport(results: [
            .failure(URLError(.timedOut)),
            .success(
                response(
                    url: "https://xtbang.top/maurya/api/share/v1/shares/K8F3Q7D2PX/meta", status: 200, contentType: "application/json",
                    body: metadata)),
            .success(
                response(
                    url: "https://xtbang.top/maurya/api/share/v1/shares/K8F3Q7D2PX/blob", status: 200,
                    contentType: ShareAPIClient.mediaType, body: blob)),
        ])
        let client = try makeClient(transport)
        let pending = try await client.fetchForPreview("K8F3Q-7D2PX")
        #expect(pending.token == "K8F3Q7D2PX")
        #expect(pending.envelope == dated)
        #expect(await transport.requests.count == 3)
    }

    @Test(
        .tags(.networking),
        arguments: [
            ShareAPIError.unexpectedContentType,
            ShareAPIError.responseTooLarge(limit: 2),
            ShareAPIError.http(status: 404, code: "SHARE_NOT_FOUND"),
        ])
    func responseFailuresAreTyped(_ expected: ShareAPIError) async throws {
        let body: Data
        let status: Int
        let contentType: String
        let headers: [String: String]
        switch expected {
        case .unexpectedContentType:
            body = Data("{}".utf8); status = 200; contentType = "text/plain"; headers = [:]
        case .responseTooLarge:
            body = Data("{}".utf8); status = 200; contentType = "application/json"; headers = ["Content-Length": "40000"]
        default:
            body = Data(#"{"error":{"code":"SHARE_NOT_FOUND"}}"#.utf8); status = 404; contentType = "application/json"; headers = [:]
        }
        let transport = FakeShareTransport(results: [
            .success(
                response(
                    url: "https://xtbang.top/maurya/api/share/v1/shares/K8F3Q7D2PX/meta",
                    status: status,
                    contentType: contentType,
                    body: body,
                    headers: headers
                ))
        ])
        let client = try makeClient(transport, retryDelays: [])
        do {
            _ = try await client.fetchMetadata("K8F3Q7D2PX")
            Issue.record("Expected typed API failure")
        } catch let error as ShareAPIError {
            switch expected {
            case .responseTooLarge:
                #expect(error == .responseTooLarge(limit: 32 * 1_024))
            default:
                #expect(error == expected)
            }
        }
    }

    @Test(.tags(.networking))
    func cancellationIsNotRetried() async throws {
        let transport = FakeShareTransport(results: [.failure(CancellationError())])
        let client = try makeClient(transport)
        await #expect(throws: ShareAPIError.cancelled) {
            try await client.fetchMetadata("K8F3Q7D2PX")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func productionOriginRejectsHTTPPortsAndOtherHosts() {
        for raw in ["http://xtbang.top", "https://xtbang.top:443", "https://example.com"] {
            #expect(throws: ShareAPIError.invalidConfiguration) {
                _ = try ShareAPIClient(origin: try #require(URL(string: raw)), transport: FakeShareTransport(results: []))
            }
        }
    }

    @Test(.tags(.networking))
    func URLSessionTransportStopsOversizedBodyDuringStreaming() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedShareURLProtocol.self]
        let transport = URLSessionShareTransport(session: URLSession(configuration: configuration))
        let request = URLRequest(url: try #require(URL(string: "https://xtbang.top/test")))

        await #expect(throws: ShareAPIError.responseTooLarge(limit: 10)) {
            try await transport.data(for: request, maximumBytes: 10)
        }
    }

    private func makeClient(
        _ transport: FakeShareTransport,
        retryDelays: [Duration] = [.zero]
    ) throws -> ShareAPIClient {
        try ShareAPIClient(
            origin: #require(URL(string: "https://xtbang.top")),
            transport: transport,
            retryDelays: retryDelays,
            sleep: { _ in }
        )
    }
}

private final class OversizedShareURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 11))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor FakeShareTransport: ShareHTTPTransport {
    private var results: [Result<(Data, URLResponse), any Error>]
    private(set) var requests: [URLRequest] = []

    init(results: [Result<(Data, URLResponse), any Error>]) {
        self.results = results
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard results.isEmpty == false else { throw URLError(.badServerResponse) }
        return try results.removeFirst().get()
    }
}

private func response(
    url: String,
    status: Int,
    contentType: String,
    body: Data,
    headers: [String: String] = [:]
) -> (Data, URLResponse) {
    var fields = headers
    fields["Content-Type"] = contentType
    let response = HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: fields
    )!
    return (body, response)
}
