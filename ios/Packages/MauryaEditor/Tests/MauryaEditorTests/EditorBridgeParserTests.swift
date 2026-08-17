import Foundation
import Testing

@testable import MauryaEditor

struct EditorBridgeParserTests {
    private let nonce = "nonce-123"

    @Test func parsesReadyAndWorkspaceEvents() throws {
        let parser = EditorBridgeParser()
        let ready = EditorBridgeEnvelope(nonce: nonce, requestID: "ready-1", type: "ready", payload: ["editor": .string("blocks")])
        let (_, readyEvent) = try parser.parse(try JSONEncoder().encode(ready), expectedNonce: nonce)
        #expect(readyEvent == .ready(.blocks))

        let workspace = EditorBridgeEnvelope(
            nonce: nonce,
            requestID: "change-1",
            type: "workspaceChanged",
            payload: ["document": .string("{\"blocks\":[]}"), "count": .number(0)]
        )
        let (_, event) = try parser.parse(try JSONEncoder().encode(workspace), expectedNonce: nonce)
        #expect(event == .workspaceChanged(document: "{\"blocks\":[]}", count: 0))
    }

    @Test func rejectsWrongVersionNonceAndUnknownType() throws {
        let parser = EditorBridgeParser()
        let wrongVersion = EditorBridgeEnvelope(
            version: 2, nonce: nonce, requestID: "id", type: "ready", payload: ["editor": .string("blocks")])
        #expect(throws: EditorBridgeError.unsupportedVersion) {
            try parser.parse(try JSONEncoder().encode(wrongVersion), expectedNonce: nonce)
        }
        let wrongNonce = EditorBridgeEnvelope(nonce: "attacker", requestID: "id", type: "ready", payload: ["editor": .string("blocks")])
        #expect(throws: EditorBridgeError.nonceMismatch) {
            try parser.parse(try JSONEncoder().encode(wrongNonce), expectedNonce: nonce)
        }
        let unknown = EditorBridgeEnvelope(nonce: nonce, requestID: "id", type: "eval", payload: [:])
        #expect(throws: EditorBridgeError.unknownType) {
            try parser.parse(try JSONEncoder().encode(unknown), expectedNonce: nonce)
        }
    }

    @Test func appliesByteSchemaAndIdentifierLimits() throws {
        var limits = EditorBridgeLimits()
        limits.maximumMessageBytes = 128
        let parser = EditorBridgeParser(limits: limits)
        #expect(throws: EditorBridgeError.messageTooLarge) {
            try parser.parse(Data(repeating: 0x20, count: 129), expectedNonce: nonce)
        }

        let invalidID = EditorBridgeEnvelope(nonce: nonce, requestID: "bad/id", type: "ready", payload: ["editor": .string("blocks")])
        #expect(throws: EditorBridgeError.invalidRequestID) {
            try EditorBridgeParser().parse(try JSONEncoder().encode(invalidID), expectedNonce: nonce)
        }

        let fractionalCount = EditorBridgeEnvelope(
            nonce: nonce,
            requestID: "id",
            type: "workspaceChanged",
            payload: ["document": .string("{}"), "count": .number(1.5)]
        )
        #expect(throws: EditorBridgeError.invalidPayload) {
            try EditorBridgeParser().parse(try JSONEncoder().encode(fractionalCount), expectedNonce: nonce)
        }
    }

    @Test func rejectsDeepPayload() throws {
        var value: BridgeValue = .null
        for _ in 0..<10 { value = .array([value]) }
        let envelope = EditorBridgeEnvelope(
            nonce: nonce, requestID: "id", type: "response", payload: ["command": .string("export"), "value": value])
        #expect(throws: EditorBridgeError.payloadTooComplex) {
            try EditorBridgeParser().parse(try JSONEncoder().encode(envelope), expectedNonce: nonce)
        }
    }

    @Test func rejectsUnknownSchemaFields() throws {
        let data = Data(
            """
            {"version":1,"nonce":"nonce-123","requestID":"id","type":"ready","payload":{"editor":"blocks"},"unexpected":true}
            """.utf8)
        #expect(throws: EditorBridgeError.malformedEnvelope) {
            try EditorBridgeParser().parse(data, expectedNonce: nonce)
        }

        let envelope = EditorBridgeEnvelope(
            nonce: nonce,
            requestID: "id",
            type: "ready",
            payload: ["editor": .string("blocks"), "unexpected": .bool(true)]
        )
        #expect(throws: EditorBridgeError.invalidPayload) {
            try EditorBridgeParser().parse(try JSONEncoder().encode(envelope), expectedNonce: nonce)
        }
    }

    @Test func validatesOutboundCommandArguments() throws {
        var limits = EditorBridgeLimits()
        limits.maximumDocumentBytes = 4
        limits.maximumDiagnosticLength = 3
        #expect(throws: EditorBridgeError.invalidPayload) { try EditorCommand.load("12345").validate(limits: limits) }
        #expect(throws: EditorBridgeError.invalidPayload) {
            try EditorCommand.editField(blockID: "bad/id", fieldName: "COLOR").validate(limits: limits)
        }
        #expect(throws: EditorBridgeError.invalidPayload) {
            try EditorCommand.diagnostic(.init(start: 0, end: 1, message: "long")).validate(limits: limits)
        }
        try EditorCommand.insertWaitAfter(target: "block-1", milliseconds: 2_000).validate(limits: limits)
    }
}
