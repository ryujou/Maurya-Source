import Testing

@testable import MauryaEditor

struct EditorBridgeStateMachineTests {
    @Test func requiresMatchingReadyBeforeCommands() throws {
        var machine = EditorBridgeStateMachine()
        machine.beginLoading(editor: .blocks, nonce: "nonce")
        #expect(throws: EditorBridgeError.invalidPayload) {
            try machine.consume(.ready(.script))
        }
        try machine.consume(.ready(.blocks))
        #expect(machine.state == .ready(nonce: "nonce", editor: .blocks))
        try machine.registerRequest("request-1")
        let firstCompletion = machine.completeRequest("request-1")
        let duplicateCompletion = machine.completeRequest("request-1")
        #expect(firstCompletion)
        #expect(!duplicateCompletion)
    }

    @Test func boundsPendingRequestsAndClearsOnTermination() throws {
        var machine = EditorBridgeStateMachine(maximumPendingRequests: 1)
        machine.beginLoading(editor: .script, nonce: "nonce")
        try machine.consume(.ready(.script))
        try machine.registerRequest("one")
        #expect(throws: EditorBridgeError.invalidRequestID) { try machine.registerRequest("two") }
        machine.terminate()
        #expect(machine.pendingRequestIDs.isEmpty)
        #expect(machine.state == .terminated)
    }
}
