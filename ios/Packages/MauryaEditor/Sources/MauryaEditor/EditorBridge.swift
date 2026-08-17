import Foundation

public enum EditorKind: String, Sendable, Codable, CaseIterable {
    case blocks
    case script
}

public struct EditorDiagnostic: Sendable, Equatable, Codable {
    public let start: Int
    public let end: Int
    public let message: String

    public init(start: Int, end: Int, message: String) {
        self.start = start
        self.end = end
        self.message = message
    }
}

public enum EditorCommand: Sendable, Equatable {
    case load(String)
    case export
    case `import`(String)
    case undo
    case redo
    case resize
    case fit
    case run
    case editField(blockID: String, fieldName: String)
    case insertWaitAfter(target: String, milliseconds: Int)
    case diagnostic(EditorDiagnostic)
    case clearDiagnostics

    var name: String {
        switch self {
        case .load: "load"
        case .export: "export"
        case .import: "import"
        case .undo: "undo"
        case .redo: "redo"
        case .resize: "resize"
        case .fit: "fit"
        case .run: "run"
        case .editField: "editField"
        case .insertWaitAfter: "insertWaitAfter"
        case .diagnostic: "diagnostic"
        case .clearDiagnostics: "clearDiagnostics"
        }
    }

    var payload: [String: BridgeValue] {
        switch self {
        case let .load(document), let .import(document):
            ["document": .string(document)]
        case let .editField(blockID, fieldName):
            ["blockID": .string(blockID), "fieldName": .string(fieldName)]
        case let .insertWaitAfter(target, milliseconds):
            ["target": .string(target), "milliseconds": .number(Double(milliseconds))]
        case let .diagnostic(value):
            ["start": .number(Double(value.start)), "end": .number(Double(value.end)), "message": .string(value.message)]
        default:
            [:]
        }
    }

    func validate(limits: EditorBridgeLimits) throws {
        func validIdentifier(_ value: String) -> Bool {
            !value.isEmpty && value.count <= limits.maximumIdentifierLength
                && value.unicodeScalars.allSatisfy {
                    CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:")).contains($0)
                }
        }
        switch self {
        case let .load(document), let .import(document):
            guard document.utf8.count <= limits.maximumDocumentBytes else { throw EditorBridgeError.invalidPayload }
        case let .editField(blockID, fieldName):
            guard validIdentifier(blockID), validIdentifier(fieldName) else { throw EditorBridgeError.invalidPayload }
        case let .insertWaitAfter(target, milliseconds):
            guard validIdentifier(target), (0...86_400_000).contains(milliseconds) else { throw EditorBridgeError.invalidPayload }
        case let .diagnostic(value):
            guard value.start >= 0, value.end >= value.start,
                value.end <= limits.maximumDocumentBytes,
                value.message.utf8.count <= limits.maximumDiagnosticLength
            else { throw EditorBridgeError.invalidPayload }
        default:
            break
        }
    }
}

public struct EditorBridgeEnvelope: Sendable, Equatable, Codable {
    public static let protocolVersion = 1

    public let version: Int
    public let nonce: String
    public let requestID: String
    public let type: String
    public let payload: [String: BridgeValue]

    public init(version: Int = protocolVersion, nonce: String, requestID: String, type: String, payload: [String: BridgeValue]) {
        self.version = version
        self.nonce = nonce
        self.requestID = requestID
        self.type = type
        self.payload = payload
    }
}

public enum EditorBridgeEvent: Sendable, Equatable {
    case ready(EditorKind)
    case workspaceChanged(document: String, count: Int)
    case sourceChanged(document: String, lines: Int)
    case saveRequested(String)
    case runRequested(String)
    case haptic(String)
    case response(command: String, value: BridgeValue?)
}

public struct EditorBridgeLimits: Sendable, Equatable {
    public var maximumMessageBytes = 1_100_000
    public var maximumDocumentBytes = 1_000_000
    public var maximumIdentifierLength = 128
    public var maximumDiagnosticLength = 8_192
    public var maximumDepth = 8
    public var maximumNodes = 128

    public init() {}
}

public enum EditorBridgeError: Error, Sendable, Equatable {
    case messageTooLarge
    case malformedEnvelope
    case unsupportedVersion
    case nonceMismatch
    case invalidRequestID
    case unknownType
    case invalidPayload
    case payloadTooComplex
}

public struct EditorBridgeParser: Sendable {
    public let limits: EditorBridgeLimits

    public init(limits: EditorBridgeLimits = .init()) { self.limits = limits }

    public func parse(_ data: Data, expectedNonce: String) throws -> (EditorBridgeEnvelope, EditorBridgeEvent) {
        guard data.count <= limits.maximumMessageBytes else { throw EditorBridgeError.messageTooLarge }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(raw.keys) == ["version", "nonce", "requestID", "type", "payload"]
        else {
            throw EditorBridgeError.malformedEnvelope
        }
        let envelope: EditorBridgeEnvelope
        do { envelope = try JSONDecoder().decode(EditorBridgeEnvelope.self, from: data) } catch {
            throw EditorBridgeError.malformedEnvelope
        }
        guard envelope.version == EditorBridgeEnvelope.protocolVersion else { throw EditorBridgeError.unsupportedVersion }
        guard envelope.nonce == expectedNonce else { throw EditorBridgeError.nonceMismatch }
        guard isIdentifier(envelope.requestID) else { throw EditorBridgeError.invalidRequestID }
        try validateComplexity(.object(envelope.payload))
        return (envelope, try event(from: envelope))
    }

    private func event(from envelope: EditorBridgeEnvelope) throws -> EditorBridgeEvent {
        let payload = envelope.payload
        switch envelope.type {
        case "ready":
            guard exactKeys(payload, ["editor"]), let raw = payload["editor"]?.string,
                let kind = EditorKind(rawValue: raw)
            else { throw EditorBridgeError.invalidPayload }
            return .ready(kind)
        case "workspaceChanged":
            guard exactKeys(payload, ["document", "count"]) else { throw EditorBridgeError.invalidPayload }
            return .workspaceChanged(document: try document(payload), count: try nonnegativeInteger(payload, "count"))
        case "sourceChanged":
            guard exactKeys(payload, ["document", "lines"]) else { throw EditorBridgeError.invalidPayload }
            return .sourceChanged(document: try document(payload), lines: try nonnegativeInteger(payload, "lines"))
        case "saveRequested":
            guard exactKeys(payload, ["document"]) else { throw EditorBridgeError.invalidPayload }
            return .saveRequested(try document(payload))
        case "runRequested":
            guard exactKeys(payload, ["document"]) else { throw EditorBridgeError.invalidPayload }
            return .runRequested(try document(payload))
        case "haptic":
            guard exactKeys(payload, ["kind"]), let kind = payload["kind"]?.string,
                isIdentifier(kind)
            else { throw EditorBridgeError.invalidPayload }
            return .haptic(kind)
        case "response":
            guard Set(payload.keys).isSubset(of: ["command", "value"]), payload["command"] != nil,
                let command = payload["command"]?.string, isIdentifier(command)
            else { throw EditorBridgeError.invalidPayload }
            return .response(command: command, value: payload["value"])
        default:
            throw EditorBridgeError.unknownType
        }
    }

    private func exactKeys(_ payload: [String: BridgeValue], _ keys: Set<String>) -> Bool { Set(payload.keys) == keys }

    private func document(_ payload: [String: BridgeValue]) throws -> String {
        guard let value = payload["document"]?.string,
            value.utf8.count <= limits.maximumDocumentBytes
        else { throw EditorBridgeError.invalidPayload }
        return value
    }

    private func nonnegativeInteger(_ payload: [String: BridgeValue], _ key: String) throws -> Int {
        guard let value = payload[key]?.integer, value >= 0, value <= 1_000_000 else { throw EditorBridgeError.invalidPayload }
        return value
    }

    private func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= limits.maximumIdentifierLength
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:")).contains($0)
            }
    }

    private func validateComplexity(_ root: BridgeValue) throws {
        var remaining = limits.maximumNodes
        func walk(_ value: BridgeValue, depth: Int) throws {
            guard depth <= limits.maximumDepth, remaining > 0 else { throw EditorBridgeError.payloadTooComplex }
            remaining -= 1
            switch value {
            case let .string(value):
                guard value.utf8.count <= limits.maximumDocumentBytes else { throw EditorBridgeError.invalidPayload }
            case let .array(values):
                for value in values { try walk(value, depth: depth + 1) }
            case let .object(values):
                for (key, value) in values {
                    guard key.count <= limits.maximumIdentifierLength else { throw EditorBridgeError.invalidPayload }
                    try walk(value, depth: depth + 1)
                }
            default: break
            }
        }
        try walk(root, depth: 0)
    }
}
