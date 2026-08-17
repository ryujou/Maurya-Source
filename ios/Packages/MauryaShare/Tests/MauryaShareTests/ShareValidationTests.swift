import Foundation
import Testing

@testable import MauryaShare

struct ShareValidationTests {
    @Test func strictJSONRejectsDuplicateKeysAndTrailingData() {
        #expect(throws: ShareValidationError.duplicateJSONKey) { try ShareEnvelopeCodec.validateJSON("{\"a\":1,\"a\":2}") }
        #expect(throws: ShareValidationError.invalidJSON) { try ShareEnvelopeCodec.validateJSON("{}[]") }
    }

    @Test func strictJSONEnforcesAndroidDepthBoundary() throws {
        let depth32 = String(repeating: "[", count: 32) + "0" + String(repeating: "]", count: 32)
        try ShareEnvelopeCodec.validateJSON(depth32)
        let depth33 = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
        #expect(throws: ShareValidationError.JSONDepthExceeded) { try ShareEnvelopeCodec.validateJSON(depth33) }
    }

    @Test func strictJSONRejectsInvalidSurrogatesAndLeadingZero() {
        #expect(throws: ShareValidationError.invalidJSON) { try ShareEnvelopeCodec.validateJSON("\"\\uD800\"") }
        #expect(throws: ShareValidationError.invalidJSON) { try ShareEnvelopeCodec.validateJSON("01") }
    }

    @Test func strictJSONEnforcesAggregateEntryLimit() {
        let oversized = "[" + Array(repeating: "0", count: ShareEnvelopeCodec.JSONMaximumEntries + 1).joined(separator: ",") + "]"
        #expect(throws: ShareValidationError.JSONLimitExceeded) {
            try ShareEnvelopeCodec.validateJSON(oversized)
        }
    }

    @Test func displayNamesAreNFCTrimmedAndBounded() throws {
        let envelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "  e\u{301}  ", ja: ""), sourceKind: .script, source: "effect \"safe\" { wait(1s); }")
        #expect(envelope.displayName.zh == "é")
        #expect(throws: ShareValidationError.invalidDisplayName) {
            try ShareEnvelopeCodec.makeEffect(
                names: ShareDisplayName(zh: String(repeating: "灯", count: 65), ja: ""), sourceKind: .script,
                source: "effect \"safe\" { wait(1s); }")
        }
    }

    @Test func multilineScriptAndPrettyBlocklySourceMatchAndroidValidation() throws {
        let script = """
            effect "Shared" {
            \tall.color("#39C5BB");
            \twait(500ms);
            }
            """
        let scriptEnvelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "多行脚本", ja: "複数行スクリプト"),
            sourceKind: .script,
            source: script
        )
        let datedScript = ShareEnvelope(
            kind: scriptEnvelope.kind,
            displayName: scriptEnvelope.displayName,
            payload: scriptEnvelope.payload,
            contentHash: scriptEnvelope.contentHash,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let scriptBlob = try Gzip.compress(
            ShareEnvelopeCodec.canonicalEnvelope(datedScript, includeCreatedAt: true),
            maximumOutput: ShareEnvelopeCodec.maximumCompressedBytes
        )
        let decodedScript = try ShareEnvelopeCodec.decodeBlob(
            scriptBlob,
            expectedSHA256: ShareEnvelopeCodec.sha256(scriptBlob)
        )
        #expect(decodedScript.payload == scriptEnvelope.payload)

        let blocks = """
            {
              "blocks": {
                "languageVersion": 0,
                "blocks": []
              }
            }
            """
        let blocksEnvelope = try ShareEnvelopeCodec.makeEffect(
            names: ShareDisplayName(zh: "积木", ja: "ブロック"),
            sourceKind: .blocks,
            source: blocks
        )
        let datedBlocks = ShareEnvelope(
            kind: blocksEnvelope.kind,
            displayName: blocksEnvelope.displayName,
            payload: blocksEnvelope.payload,
            contentHash: blocksEnvelope.contentHash,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let blocksBlob = try Gzip.compress(
            ShareEnvelopeCodec.canonicalEnvelope(datedBlocks, includeCreatedAt: true),
            maximumOutput: ShareEnvelopeCodec.maximumCompressedBytes
        )
        let decodedBlocks = try ShareEnvelopeCodec.decodeBlob(
            blocksBlob,
            expectedSHA256: ShareEnvelopeCodec.sha256(blocksBlob)
        )
        #expect(decodedBlocks.payload == blocksEnvelope.payload)
    }

    @Test func sourceSizeAndUnsafeControlCharactersAreRejected() {
        for character in ["\0", "\u{000B}", "\u{000C}", "\u{007F}", "\u{202E}", "\u{2066}"] {
            #expect(throws: ShareValidationError.invalidPayload) {
                try ShareEnvelopeCodec.makeEffect(
                    names: ShareDisplayName(zh: "安全", ja: ""), sourceKind: .script,
                    source: "bad\(character)source"
                )
            }
        }
        #expect(throws: ShareValidationError.invalidPayload) {
            try ShareEnvelopeCodec.makeEffect(
                names: ShareDisplayName(zh: "安全", ja: ""), sourceKind: .script,
                source: String(repeating: "a", count: ShareEnvelopeCodec.maximumSourceBytes + 1))
        }
    }
}
