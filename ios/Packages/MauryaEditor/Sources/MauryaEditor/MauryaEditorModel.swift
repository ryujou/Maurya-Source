#if os(iOS)
    import Combine
    import Foundation

    @MainActor
    public final class MauryaEditorModel: ObservableObject {
        public enum Phase: Sendable, Equatable {
            case idle
            case loading
            case ready
            case failed(String)
            case terminated
        }

        @Published public private(set) var phase: Phase = .idle
        @Published public private(set) var bundleVersion: String?
        @Published public private(set) var bundleSHA256: String?
        @Published public private(set) var latestDocument: String?

        public var onEvent: ((EditorBridgeEvent) -> Void)?
        public var onRejectedMessage: ((EditorBridgeError) -> Void)?

        private var machine = EditorBridgeStateMachine()
        private let parser: EditorBridgeParser
        private let limits: EditorBridgeLimits
        private let autosaveStore: EditorAutosaveStore?
        private var autosaveTask: Task<Void, Never>?
        private var commandSink: ((EditorBridgeEnvelope) -> Void)?
        private var nonce: String?

        public init(autosaveURL: URL? = nil, limits: EditorBridgeLimits = .init()) {
            self.limits = limits
            parser = EditorBridgeParser(limits: limits)
            autosaveStore = autosaveURL.map { EditorAutosaveStore(fileURL: $0, maximumBytes: limits.maximumDocumentBytes) }
        }

        deinit { autosaveTask?.cancel() }

        public func send(_ command: EditorCommand) throws {
            guard let nonce, let commandSink else { throw EditorBridgeError.invalidPayload }
            try command.validate(limits: limits)
            let requestID = UUID().uuidString.lowercased()
            try machine.registerRequest(requestID)
            commandSink(
                EditorBridgeEnvelope(
                    nonce: nonce,
                    requestID: requestID,
                    type: "command",
                    payload: ["command": .string(command.name), "arguments": .object(command.payload)]
                ))
        }

        func attach(commandSink: @escaping (EditorBridgeEnvelope) -> Void) { self.commandSink = commandSink }

        func beginLoading(editor: EditorKind, nonce: String, bundleVersion: String, bundleSHA256: String) {
            autosaveTask?.cancel()
            self.nonce = nonce
            self.bundleVersion = bundleVersion
            self.bundleSHA256 = bundleSHA256
            machine.beginLoading(editor: editor, nonce: nonce)
            phase = .loading
        }

        func receive(_ data: Data) {
            guard let nonce else { return }
            do {
                let (envelope, event) = try parser.parse(data, expectedNonce: nonce)
                try machine.consume(event)
                if case .ready = event { phase = .ready }
                if case .response = event, !machine.completeRequest(envelope.requestID) {
                    throw EditorBridgeError.invalidRequestID
                }
                switch event {
                case let .workspaceChanged(document, _), let .sourceChanged(document, _):
                    latestDocument = document
                    scheduleAutosave(document)
                default:
                    break
                }
                onEvent?(event)
            } catch let error as EditorBridgeError {
                onRejectedMessage?(error)
            } catch {
                onRejectedMessage?(.malformedEnvelope)
            }
        }

        func restoredDocument(fallback: String) async -> String {
            guard let autosaveStore else { return fallback }
            return (try? await autosaveStore.restore()) ?? fallback
        }

        func processTerminated() {
            machine.terminate()
            phase = .terminated
        }

        func fail(_ error: Error) {
            let message = String(describing: error)
            machine.fail(message)
            phase = .failed(message)
        }

        func detach() {
            autosaveTask?.cancel()
            autosaveTask = nil
            commandSink = nil
            nonce = nil
            machine.terminate()
            // UIViewRepresentable dismantling runs while SwiftUI invalidates its
            // attribute graph. Publishing from that callback can overlap the
            // graph mutation and trigger Swift's exclusivity trap on a device.
            // A replacement coordinator calls beginLoading(), while a removed
            // view releases its StateObject, so no observable transition is
            // required here.
        }

        private func scheduleAutosave(_ document: String) {
            guard let autosaveStore else { return }
            autosaveTask?.cancel()
            autosaveTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    try Task.checkCancellation()
                    try await autosaveStore.save(document)
                } catch is CancellationError {
                    return
                } catch {
                    fail(error)
                }
            }
        }
    }
#endif
