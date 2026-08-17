import Foundation

public struct EditorBridgeStateMachine: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case idle
        case loading(nonce: String, editor: EditorKind)
        case ready(nonce: String, editor: EditorKind)
        case failed(String)
        case terminated
    }

    public private(set) var state: State = .idle
    public private(set) var pendingRequestIDs: Set<String> = []
    public let maximumPendingRequests: Int

    public init(maximumPendingRequests: Int = 32) { self.maximumPendingRequests = maximumPendingRequests }

    public mutating func beginLoading(editor: EditorKind, nonce: String) {
        pendingRequestIDs.removeAll(keepingCapacity: true)
        state = .loading(nonce: nonce, editor: editor)
    }

    public mutating func consume(_ event: EditorBridgeEvent) throws {
        switch (state, event) {
        case let (.loading(nonce, expected), .ready(actual)) where expected == actual:
            state = .ready(nonce: nonce, editor: expected)
        case (.ready, .ready):
            break
        case (.ready, _):
            break
        default:
            throw EditorBridgeError.invalidPayload
        }
    }

    public mutating func registerRequest(_ requestID: String) throws {
        guard case .ready = state, pendingRequestIDs.count < maximumPendingRequests,
            pendingRequestIDs.insert(requestID).inserted
        else { throw EditorBridgeError.invalidRequestID }
    }

    public mutating func completeRequest(_ requestID: String) -> Bool {
        pendingRequestIDs.remove(requestID) != nil
    }

    public mutating func fail(_ message: String) {
        pendingRequestIDs.removeAll(keepingCapacity: false)
        state = .failed(message)
    }

    public mutating func terminate() {
        pendingRequestIDs.removeAll(keepingCapacity: false)
        state = .terminated
    }
}
