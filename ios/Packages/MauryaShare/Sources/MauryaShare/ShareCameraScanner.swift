import AVFoundation
import Foundation

public enum ShareCameraScannerError: Error, Sendable, Equatable {
    case alreadyRunning
    case noVideoDevice
    case cannotAddInput
    case cannotAddOutput
    case configurationFailed
}

public enum ShareCameraSuspensionReason: Sendable, Hashable {
    case applicationBackground
    case sessionInterruption
}

public enum ShareCameraScannerState: Sendable, Equatable {
    case idle
    case starting
    case running
    case suspended(Set<ShareCameraSuspensionReason>)
    case stopped
    case failed(ShareCameraScannerError)
}

enum ShareCameraScannerEvent: Sendable, Equatable {
    case requestStart
    case startSucceeded
    case suspend(ShareCameraSuspensionReason)
    case resume(ShareCameraSuspensionReason)
    case requestStop
    case cancel
    case fail(ShareCameraScannerError)
}

enum ShareCameraScannerAction: Sendable, Equatable {
    case configureAndStart
    case startSession
    case stopSession
    case finishStream
}

struct ShareCameraScannerStateMachine: Sendable {
    private(set) var state: ShareCameraScannerState = .idle

    mutating func handle(_ event: ShareCameraScannerEvent) -> [ShareCameraScannerAction] {
        switch event {
        case .requestStart:
            switch state {
            case .idle, .stopped, .failed:
                state = .starting
                return [.configureAndStart]
            case .starting, .running, .suspended:
                return []
            }

        case .startSucceeded:
            guard state == .starting else { return [] }
            state = .running
            return []

        case let .suspend(reason):
            switch state {
            case .running:
                state = .suspended([reason])
                return [.stopSession]
            case let .suspended(reasons):
                var next = reasons
                next.insert(reason)
                state = .suspended(next)
                return []
            case .idle, .starting, .stopped, .failed:
                return []
            }

        case let .resume(reason):
            guard case let .suspended(reasons) = state else { return [] }
            var next = reasons
            next.remove(reason)
            if next.isEmpty {
                state = .running
                return [.startSession]
            }
            state = .suspended(next)
            return []

        case .requestStop, .cancel:
            switch state {
            case .idle, .stopped:
                state = .stopped
                return []
            case .starting, .running, .suspended, .failed:
                state = .stopped
                return [.stopSession, .finishStream]
            }

        case let .fail(error):
            state = .failed(error)
            return [.stopSession, .finishStream]
        }
    }
}

/// Owns only the capture mechanics. The App remains responsible for camera
/// authorization, usage-description text, navigation, and forwarding lifecycle
/// and AVCaptureSession interruption notifications to this actor.
public actor AVFoundationShareQRCodePayloadProvider {
    private var machine = ShareCameraScannerStateMachine()
    private var session: AVCaptureSession?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var delegate: ShareMetadataOutputDelegate?
    private var continuation: AsyncStream<String>.Continuation?

    public init() {}

    public var state: ShareCameraScannerState { machine.state }

    /// Explicitly starts capture and returns a single-consumer, newest-value
    /// stream. Call `stop()` on every exit path, or prefer `withPayloads`.
    public func start() throws -> AsyncStream<String> {
        guard machine.state != .starting, machine.state != .running else {
            throw ShareCameraScannerError.alreadyRunning
        }
        let actions = machine.handle(.requestStart)
        guard actions == [.configureAndStart] else { throw ShareCameraScannerError.configurationFailed }

        let pair = Self.makePayloadStream()
        do {
            let configured = try configureSession(continuation: pair.continuation)
            session = configured.session
            metadataOutput = configured.output
            delegate = configured.delegate
            continuation = pair.continuation
            configured.session.startRunning()
            _ = machine.handle(.startSucceeded)
            return pair.stream
        } catch let error as ShareCameraScannerError {
            pair.continuation.finish()
            apply(machine.handle(.fail(error)))
            throw error
        } catch {
            pair.continuation.finish()
            apply(machine.handle(.fail(.configurationFailed)))
            throw ShareCameraScannerError.configurationFailed
        }
    }

    /// Cancellation-safe structured form. Cancelling the consuming task
    /// finishes the bounded stream; the actor then stops capture before return.
    public func withPayloads<Result: Sendable>(
        _ operation: @Sendable (AsyncStream<String>) async throws -> Result
    ) async throws -> Result {
        let stream = try start()
        guard let activeContinuation = continuation else {
            stop()
            throw ShareCameraScannerError.configurationFailed
        }
        let ownedSession = session
        return try await withTaskCancellationHandler {
            do {
                let result = try await operation(stream)
                try Task.checkCancellation()
                stop(ifOwnedBy: ownedSession)
                return result
            } catch {
                stop(ifOwnedBy: ownedSession)
                throw error
            }
        } onCancel: {
            activeContinuation.finish()
        }
    }

    public func stop() {
        apply(machine.handle(.requestStop))
        clearCaptureGraph()
    }

    public func cancel() {
        apply(machine.handle(.cancel))
        clearCaptureGraph()
    }

    public func applicationDidEnterBackground() {
        apply(machine.handle(.suspend(.applicationBackground)))
    }

    public func applicationWillEnterForeground() {
        apply(machine.handle(.resume(.applicationBackground)))
    }

    public func sessionInterruptionBegan() {
        apply(machine.handle(.suspend(.sessionInterruption)))
    }

    public func sessionInterruptionEnded() {
        apply(machine.handle(.resume(.sessionInterruption)))
    }

    public func sessionFailed() {
        apply(machine.handle(.fail(.configurationFailed)))
        clearCaptureGraph()
    }

    nonisolated static func makePayloadStream() -> (
        stream: AsyncStream<String>,
        continuation: AsyncStream<String>.Continuation
    ) {
        AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(1))
    }

    private func configureSession(
        continuation: AsyncStream<String>.Continuation
    ) throws -> (session: AVCaptureSession, output: AVCaptureMetadataOutput, delegate: ShareMetadataOutputDelegate) {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw ShareCameraScannerError.noVideoDevice
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw ShareCameraScannerError.configurationFailed
        }

        let session = AVCaptureSession()
        let output = AVCaptureMetadataOutput()
        let delegate = ShareMetadataOutputDelegate(continuation: continuation)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw ShareCameraScannerError.cannotAddInput }
        session.addInput(input)
        guard session.canAddOutput(output) else { throw ShareCameraScannerError.cannotAddOutput }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]
        return (session, output, delegate)
    }

    private func apply(_ actions: [ShareCameraScannerAction]) {
        for action in actions {
            switch action {
            case .configureAndStart:
                break
            case .startSession:
                session?.startRunning()
            case .stopSession:
                session?.stopRunning()
            case .finishStream:
                continuation?.finish()
            }
        }
    }

    private func clearCaptureGraph() {
        continuation?.finish()
        continuation = nil
        metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)
        metadataOutput = nil
        delegate = nil
        session = nil
    }

    private func stop(ifOwnedBy ownedSession: AVCaptureSession?) {
        guard session === ownedSession else { return }
        stop()
    }
}

private final class ShareMetadataOutputDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, Sendable {
    private let continuation: AsyncStream<String>.Continuation
    private let parser = StrictShareScannedPayloadParser()

    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for case let object as AVMetadataMachineReadableCodeObject in metadataObjects
        where object.type == .qr {
            guard let value = object.stringValue,
                let token = try? parser.parseScannedPayload(value)
            else { continue }
            continuation.yield(token)
            return
        }
    }
}
