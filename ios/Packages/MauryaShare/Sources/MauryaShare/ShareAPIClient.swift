import Foundation

public struct CreatedShare: Sendable, Equatable {
    public let token: String
    public let shareURL: URL
    public let expiresAt: Date
    public let blobSHA256: String
    public let moderationVersion: String

    public init(
        token: String,
        shareURL: URL,
        expiresAt: Date,
        blobSHA256: String,
        moderationVersion: String
    ) {
        self.token = token
        self.shareURL = shareURL
        self.expiresAt = expiresAt
        self.blobSHA256 = blobSHA256
        self.moderationVersion = moderationVersion
    }
}

public struct ShareMetadata: Sendable, Equatable {
    public let kind: ShareKind
    public let createdAt: Date
    public let expiresAt: Date
    public let expiresInSeconds: Int
    public let compressedBytes: Int
    public let blobSHA256: String

    public init(
        kind: ShareKind,
        createdAt: Date,
        expiresAt: Date,
        expiresInSeconds: Int,
        compressedBytes: Int,
        blobSHA256: String
    ) {
        self.kind = kind
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.expiresInSeconds = expiresInSeconds
        self.compressedBytes = compressedBytes
        self.blobSHA256 = blobSHA256
    }
}

public struct PendingShareImport: Sendable, Equatable {
    public let token: String
    public let metadata: ShareMetadata
    public let envelope: ShareEnvelope

    public init(token: String, metadata: ShareMetadata, envelope: ShareEnvelope) {
        self.token = token
        self.metadata = metadata
        self.envelope = envelope
    }
}

public enum ShareAPIError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidResponse
    case unexpectedEndpoint
    case unexpectedContentType
    case responseTooLarge(limit: Int)
    case invalidContract
    case http(status: Int, code: String)
    case offline
    case timedOut
    case TLSFailure
    case cancelled
    case transport
}

public protocol ShareHTTPTransport: Sendable {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse)
}

public struct URLSessionShareTransport: ShareHTTPTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        guard maximumBytes >= 0 else { throw ShareAPIError.invalidConfiguration }
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumBytes) {
            throw ShareAPIError.responseTooLarge(limit: maximumBytes)
        }
        var data = Data()
        data.reserveCapacity(maximumBytes)
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw ShareAPIError.responseTooLarge(limit: maximumBytes)
            }
            data.append(byte)
        }
        return (data, response)
    }

    public static func production(
        requestTimeout: TimeInterval = 10,
        resourceTimeout: TimeInterval = 15
    ) -> Self {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: RejectRedirectDelegate(), delegateQueue: nil)
        return Self(session: session)
    }
}

private final class RejectRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct ShareAPIClient: Sendable {
    public static let mediaType = "application/vnd.maurya.share+gzip"

    private let origin: URL
    private let transport: any ShareHTTPTransport
    private let requestTimeout: TimeInterval
    private let retryDelays: [Duration]
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        origin: URL,
        transport: any ShareHTTPTransport,
        requestTimeout: TimeInterval = 10,
        retryDelays: [Duration] = [.milliseconds(250), .milliseconds(750)],
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) throws {
        guard Self.isAllowedOrigin(origin), requestTimeout > 0 else {
            throw ShareAPIError.invalidConfiguration
        }
        self.origin = origin
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    public static func production() throws -> Self {
        guard let origin = URL(string: ShareToken.origin) else { throw ShareAPIError.invalidConfiguration }
        return try Self(origin: origin, transport: URLSessionShareTransport.production())
    }

    public func create(_ envelope: ShareEnvelope, idempotencyKey: UUID = UUID()) async throws -> CreatedShare {
        try Task.checkCancellation()
        let body = try ShareEnvelopeCodec.encodeRequest(envelope)
        guard body.count <= ShareEnvelopeCodec.maximumCompressedBytes else {
            throw ShareValidationError.compressedSizeExceeded
        }
        var request = try makeRequest(path: "/maurya/api/share/v1/shares", method: "POST")
        request.httpBody = body
        request.setValue(Self.mediaType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let data = try await execute(request, maximumBytes: 64 * 1_024, expectedContentType: "application/json")
        // The production service includes metadata such as `schema`, `kind`,
        // `createdAt`, and `expiresInSeconds` in addition to the Android
        // creation contract. Require every field consumed by both apps while
        // allowing forward-compatible server metadata.
        let root = try contractObject(
            data,
            keys: ["token", "shareUrl", "expiresAt", "blobSha256", "moderationVersion"],
            allowsAdditionalKeys: true
        )
        let token = try ShareToken.parse(try contractString(root, "token"))
        let shareURL = try ShareToken.canonicalURL(token)
        guard try contractString(root, "shareUrl") == shareURL.absoluteString,
            let expiresAt = parseDate(try contractString(root, "expiresAt")),
            isHash(try contractString(root, "blobSha256"))
        else {
            throw ShareAPIError.invalidContract
        }
        return CreatedShare(
            token: token,
            shareURL: shareURL,
            expiresAt: expiresAt,
            blobSHA256: try contractString(root, "blobSha256"),
            moderationVersion: try contractString(root, "moderationVersion")
        )
    }

    public func fetchMetadata(_ rawToken: String) async throws -> (token: String, metadata: ShareMetadata) {
        let token = try ShareToken.parse(rawToken)
        let request = try makeRequest(path: "/maurya/api/share/v1/shares/\(token)/meta", method: "GET")
        let data = try await executeGET(request, maximumBytes: 32 * 1_024, expectedContentType: "application/json")
        let root = try contractObject(
            data,
            keys: ["kind", "createdAt", "expiresAt", "expiresInSeconds", "compressedBytes", "blobSha256"]
        )
        guard let kind = ShareKind(rawValue: try contractString(root, "kind")),
            let createdAt = parseDate(try contractString(root, "createdAt")),
            let expiresAt = parseDate(try contractString(root, "expiresAt")),
            case let .integer(expiresInSeconds) = root["expiresInSeconds"],
            (0...604_800).contains(expiresInSeconds),
            case let .integer(compressedBytes) = root["compressedBytes"],
            (1...ShareEnvelopeCodec.maximumCompressedBytes).contains(compressedBytes),
            isHash(try contractString(root, "blobSha256"))
        else {
            throw ShareAPIError.invalidContract
        }
        return (
            token,
            ShareMetadata(
                kind: kind,
                createdAt: createdAt,
                expiresAt: expiresAt,
                expiresInSeconds: expiresInSeconds,
                compressedBytes: compressedBytes,
                blobSHA256: try contractString(root, "blobSha256")
            )
        )
    }

    public func fetchForPreview(_ rawToken: String) async throws -> PendingShareImport {
        let result = try await fetchMetadata(rawToken)
        try Task.checkCancellation()
        let request = try makeRequest(path: "/maurya/api/share/v1/shares/\(result.token)/blob", method: "GET")
        let blob = try await executeGET(
            request,
            maximumBytes: ShareEnvelopeCodec.maximumCompressedBytes,
            expectedContentType: Self.mediaType
        )
        guard blob.count == result.metadata.compressedBytes else { throw ShareAPIError.invalidContract }
        let envelope = try ShareEnvelopeCodec.decodeBlob(blob, expectedSHA256: result.metadata.blobSHA256)
        guard envelope.kind == result.metadata.kind else { throw ShareValidationError.kindMismatch }
        return PendingShareImport(token: result.token, metadata: result.metadata, envelope: envelope)
    }

    private func executeGET(
        _ request: URLRequest,
        maximumBytes: Int,
        expectedContentType: String
    ) async throws -> Data {
        for attempt in 0...retryDelays.count {
            do {
                return try await execute(request, maximumBytes: maximumBytes, expectedContentType: expectedContentType)
            } catch let error as ShareAPIError {
                guard attempt < retryDelays.count, shouldRetry(error) else { throw error }
                do {
                    try Task.checkCancellation()
                    try await sleep(retryDelays[attempt])
                } catch is CancellationError {
                    throw ShareAPIError.cancelled
                }
            }
        }
        throw ShareAPIError.transport
    }

    private func execute(
        _ request: URLRequest,
        maximumBytes: Int,
        expectedContentType: String
    ) async throws -> Data {
        do {
            try Task.checkCancellation()
            let (data, response) = try await transport.data(for: request, maximumBytes: maximumBytes)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw ShareAPIError.invalidResponse }
            guard let responseURL = http.url, Self.isAllowedResponseURL(responseURL, origin: origin) else {
                throw ShareAPIError.unexpectedEndpoint
            }
            if http.expectedContentLength > Int64(maximumBytes) { throw ShareAPIError.responseTooLarge(limit: maximumBytes) }
            guard data.count <= maximumBytes else { throw ShareAPIError.responseTooLarge(limit: maximumBytes) }
            guard (200..<300).contains(http.statusCode) else {
                throw ShareAPIError.http(status: http.statusCode, code: serverErrorCode(data))
            }
            let actualType = http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard actualType == expectedContentType.lowercased() else { throw ShareAPIError.unexpectedContentType }
            return data
        } catch is CancellationError {
            throw ShareAPIError.cancelled
        } catch let error as ShareAPIError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw ShareAPIError.cancelled
            case .timedOut: throw ShareAPIError.timedOut
            case .notConnectedToInternet, .networkConnectionLost: throw ShareAPIError.offline
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
                throw ShareAPIError.TLSFailure
            default: throw ShareAPIError.transport
            }
        } catch {
            throw ShareAPIError.transport
        }
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard path.hasPrefix("/maurya/api/share/v1/"), path.contains("..") == false,
            let url = URL(string: path, relativeTo: origin)?.absoluteURL,
            Self.isAllowedResponseURL(url, origin: origin)
        else {
            throw ShareAPIError.invalidConfiguration
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = method
        return request
    }

    private func shouldRetry(_ error: ShareAPIError) -> Bool {
        switch error {
        case .offline, .timedOut, .transport: true
        case let .http(status, _): status == 429 || (500...599).contains(status)
        default: false
        }
    }

    private static func isAllowedOrigin(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https" && components.host == "xtbang.top" && components.port == nil && components.user == nil
            && components.password == nil && (components.path.isEmpty || components.path == "/") && components.query == nil
            && components.fragment == nil
    }

    private static func isAllowedResponseURL(_ url: URL, origin: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let originComponents = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        else { return false }
        return components.scheme == "https" && components.host == originComponents.host && components.port == nil && components.user == nil
            && components.password == nil && components.query == nil && components.fragment == nil
    }
}

extension ShareAPIClient: ShareRemoteServing {}

private func contractObject(
    _ data: Data,
    keys: Set<String>,
    allowsAdditionalKeys: Bool = false
) throws -> [String: JSONValue] {
    let value = try StrictJSON.parse(data, maxDepth: 8, maxEntries: 64, maxStringBytes: 4_096)
    guard case let .object(object) = value else { throw ShareAPIError.invalidContract }
    let actualKeys = Set(object.keys)
    guard allowsAdditionalKeys ? keys.isSubset(of: actualKeys) : actualKeys == keys else {
        throw ShareAPIError.invalidContract
    }
    return object
}

private func contractString(_ object: [String: JSONValue], _ key: String) throws -> String {
    guard case let .string(value) = object[key] else { throw ShareAPIError.invalidContract }
    return value
}

private func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func isHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
}

private func serverErrorCode(_ data: Data) -> String {
    guard let value = try? StrictJSON.parse(data, maxDepth: 4, maxEntries: 16, maxStringBytes: 1_024),
        case let .object(root) = value
    else { return "INVALID_REQUEST" }
    if case let .string(code) = root["code"] { return code }
    if case let .object(error) = root["error"], case let .string(code) = error["code"] { return code }
    return "INVALID_REQUEST"
}
