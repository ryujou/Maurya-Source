import Foundation
import Testing

@testable import MauryaShare

struct ShareCodecTests {
    @Test func sharedRepositoryFixtureCoversCanonicalGzipAndHashes() throws {
        let fixture = try #require(try sharedShareFixtures().first)
        let envelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: fixture.displayName.zh, ja: fixture.displayName.ja),
            sourceKind: try #require(EffectSourceKind(rawValue: fixture.sourceKind)),
            source: fixture.source
        )

        #expect(envelope.contentHash == fixture.contentHash)
        #expect(
            try ShareEnvelopeCodec.canonicalEnvelope(envelope, includeCreatedAt: false)
                == Data(fixture.requestCanonicalUtf8.utf8)
        )
        let requestGzip = try ShareEnvelopeCodec.encodeRequest(envelope)
        #expect(
            try Gzip.decompress(requestGzip, maximumOutput: ShareEnvelopeCodec.maximumUncompressedBytes)
                == Data(fixture.requestCanonicalUtf8.utf8)
        )

        let serverGzip = try Data(hexadecimal: fixture.serverGzipHex)
        #expect(ShareEnvelopeCodec.sha256(serverGzip) == fixture.serverBlobSha256)
        #expect(
            try Gzip.decompress(serverGzip, maximumOutput: ShareEnvelopeCodec.maximumUncompressedBytes)
                == Data(fixture.serverCanonicalUtf8.utf8)
        )
        let decoded = try ShareEnvelopeCodec.decodeBlob(
            serverGzip,
            expectedSHA256: fixture.serverBlobSha256
        )
        #expect(decoded.contentHash == fixture.contentHash)
        #expect(decoded.createdAt == ISO8601DateFormatter().date(from: fixture.createdAt))
    }

    @Test func contentHashMatchesAndroidAndPythonGoldenVector() throws {
        let payload = EffectSharePayload(sourceKind: .script, editorSchema: 4, programSchema: 6, source: "effect \"星空\" { wait(1s); }")
        let hash = try ShareEnvelopeCodec.contentHash(
            kind: .effect, names: ShareDisplayName(zh: "测试", ja: "テスト"), payload: .effect(payload))
        #expect(hash == "3c601b0d69f73de53db28a4ef8525094cdd8cf4bacc87c4eb33c909ac23b4b4f")
    }

    @Test func contentHashMatchesEscapingAndNonBMPGoldenVector() throws {
        let payload = EffectSharePayload(sourceKind: .script, editorSchema: 4, programSchema: 6, source: "</script>\u{2028}😀\n")
        let hash = try ShareEnvelopeCodec.contentHash(kind: .effect, names: ShareDisplayName(zh: "名字😀", ja: ""), payload: .effect(payload))
        #expect(hash == "c7c512390d163daddf80c420d53bf8162e107600601a18e7f1d7d023a455ae12")
    }

    @Test func canonicalEnvelopeSortsKeysAndUsesUTF8() throws {
        let envelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "测试", ja: "テスト"), sourceKind: .script, source: "effect \"星空\" { wait(1s); }")
        let bytes = try ShareEnvelopeCodec.canonicalEnvelope(envelope, includeCreatedAt: false)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(text.hasPrefix("{\"contentHash\":"))
        #expect(text.contains("\"displayName\":{\"ja\":\"テスト\",\"zh\":\"测试\"}"))
        #expect(text.hasSuffix("\"schema\":1}"))
    }

    @Test func decodeBlobRoundTripsServerEnvelope() throws {
        let source = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "星空", ja: "星空"), sourceKind: .blocks, source: "{\"blocks\":[] }")
        let dated = ShareEnvelope(
            kind: source.kind, displayName: source.displayName, payload: source.payload, contentHash: source.contentHash,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let canonical = try ShareEnvelopeCodec.canonicalEnvelope(dated, includeCreatedAt: true)
        let compressed = try Gzip.compress(canonical, maximumOutput: ShareEnvelopeCodec.maximumCompressedBytes)
        let decoded = try ShareEnvelopeCodec.decodeBlob(compressed, expectedSHA256: ShareEnvelopeCodec.sha256(compressed))
        #expect(decoded.kind == .effect)
        #expect(decoded.displayName == dated.displayName)
        #expect(decoded.payload == dated.payload)
    }

    @Test func wrongBlobHashIsRejectedBeforeInflation() {
        #expect(throws: ShareValidationError.invalidHash) {
            try ShareEnvelopeCodec.decodeBlob(Data([1, 2, 3]), expectedSHA256: String(repeating: "0", count: 64))
        }
    }

    @Test func gzipExpansionLimitRejectsBomb() throws {
        let expanded = Data(repeating: 0x41, count: ShareEnvelopeCodec.maximumUncompressedBytes + 1)
        let compressed = try Gzip.compress(expanded, maximumOutput: ShareEnvelopeCodec.maximumCompressedBytes)
        #expect(throws: ShareValidationError.uncompressedSizeExceeded) {
            try Gzip.decompress(compressed, maximumOutput: ShareEnvelopeCodec.maximumUncompressedBytes)
        }
    }

    @Test func gzipRejectsTrailingMemberAndBadCRC() throws {
        let compressed = try Gzip.compress(Data("{}".utf8), maximumOutput: 1_024)
        #expect(throws: ShareValidationError.invalidGzip) { try Gzip.decompress(compressed + compressed, maximumOutput: 1_024) }
        var corrupted = compressed
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 1
        #expect(throws: ShareValidationError.invalidGzip) { try Gzip.decompress(corrupted, maximumOutput: 1_024) }
    }
}

private struct SharedShareVectorDocument: Decodable {
    let shareEnvelopes: [SharedShareVector]
}

private struct SharedShareVector: Decodable {
    struct DisplayName: Decodable {
        let zh: String
        let ja: String
    }

    let displayName: DisplayName
    let sourceKind: String
    let source: String
    let contentHash: String
    let requestCanonicalUtf8: String
    let serverCanonicalUtf8: String
    let serverGzipHex: String
    let serverBlobSha256: String
    let createdAt: String
}

private func sharedShareFixtures() throws -> [SharedShareVector] {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(
        contentsOf: repositoryRoot.appending(path: "protocol/golden-vectors.json")
    )
    return try JSONDecoder().decode(SharedShareVectorDocument.self, from: data).shareEnvelopes
}

private extension Data {
    init(hexadecimal: String) throws {
        guard hexadecimal.count.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
        self.init(capacity: hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let end = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<end], radix: 16) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            append(byte)
            index = end
        }
    }
}
