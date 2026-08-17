import Foundation
import MauryaProtocol

public actor BluetoothTransactionQueue {
    public typealias Writer = @Sendable (Data, ConnectionGeneration) async throws -> Void

    private struct Pending {
        let id: UUID
        let request: Data
        let generation: ConnectionGeneration
        let timeout: Duration
        let continuation: CheckedContinuation<Data, any Error>
    }

    private let maximumPendingCount: Int
    private let writer: Writer
    private var decoder: ModbusFrameDecoder
    private var pending: [Pending] = []
    private var active: Pending?
    private var writeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isClosed = false

    public init(
        maximumPendingCount: Int,
        writer: @escaping Writer
    ) throws {
        guard maximumPendingCount > 0 else {
            throw BluetoothFailure(.queueFull, detail: "Queue capacity must be positive")
        }
        self.maximumPendingCount = maximumPendingCount
        self.writer = writer
        self.decoder = try ModbusFrameDecoder()
    }

    public var pendingCount: Int {
        pending.count + (active == nil ? 0 : 1)
    }

    public func transact(
        _ request: Data,
        generation: ConnectionGeneration,
        timeout: Duration
    ) async throws -> Data {
        try Task.checkCancellation()
        let id = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    Pending(
                        id: id,
                        request: request,
                        generation: generation,
                        timeout: timeout,
                        continuation: continuation
                    )
                )
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    /// Feeds arbitrary notification fragments into the bounded protocol
    /// decoder. Only a frame matching the active request can complete it.
    public func receive(_ bytes: Data, generation: ConnectionGeneration) {
        guard isClosed == false else { return }
        guard active?.generation == generation else { return }

        do {
            let batch = try decoder.append(bytes)
            for frame in batch.frames {
                guard let current = active,
                    current.generation == generation,
                    ModbusResponseMatcher.matches(request: current.request, response: frame)
                else {
                    continue
                }
                finishActive(.success(frame), id: current.id)
                break
            }
        } catch {
            finishActive(
                .failure(BluetoothFailure(.protocolDecodeFailed, detail: String(describing: error))),
                id: active?.id
            )
        }
    }

    public func invalidate(
        generation: ConnectionGeneration,
        error: BluetoothFailure = .init(.staleConnection)
    ) {
        if active?.generation == generation {
            finishActive(.failure(error), id: active?.id, startNext: false)
        }

        let invalidated = pending.filter { $0.generation == generation }
        pending.removeAll { $0.generation == generation }
        for item in invalidated {
            item.continuation.resume(throwing: error)
        }
        pump()
    }

    public func close() {
        guard isClosed == false else { return }
        isClosed = true
        let error = BluetoothFailure(.disconnected, detail: "Transaction queue closed")
        writeTask?.cancel()
        timeoutTask?.cancel()
        writeTask = nil
        timeoutTask = nil
        decoder.reset()

        if let active {
            self.active = nil
            active.continuation.resume(throwing: error)
        }
        let waiting = pending
        pending.removeAll(keepingCapacity: false)
        for item in waiting {
            item.continuation.resume(throwing: error)
        }
    }

    private func enqueue(_ item: Pending) {
        guard isClosed == false else {
            item.continuation.resume(
                throwing: BluetoothFailure(.disconnected, detail: "Transaction queue closed")
            )
            return
        }
        guard pendingCount < maximumPendingCount else {
            item.continuation.resume(
                throwing: BluetoothFailure(
                    .queueFull,
                    detail: "At most \(maximumPendingCount) transactions may be pending"
                )
            )
            return
        }
        pending.append(item)
        pump()
    }

    private func pump() {
        guard isClosed == false, active == nil, pending.isEmpty == false else { return }
        decoder.reset()
        let next = pending.removeFirst()
        active = next
        writeTask = Task { [weak self] in
            guard let self else { return }
            await self.performWrite(id: next.id)
        }
    }

    private func performWrite(id: UUID) async {
        guard let item = active, item.id == id else { return }
        do {
            try Task.checkCancellation()
            try await writer(item.request, item.generation)
            try Task.checkCancellation()
            guard active?.id == id else { return }
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: item.timeout)
                    await self?.timedOut(id: id)
                } catch is CancellationError {
                    // Completion, disconnect, or caller cancellation owns cleanup.
                } catch {
                    await self?.failedToWrite(id: id, error: error)
                }
            }
        } catch is CancellationError {
            guard active?.id == id else { return }
            finishActive(.failure(CancellationError()), id: id)
        } catch {
            failedToWrite(id: id, error: error)
        }
    }

    private func failedToWrite(id: UUID, error: any Error) {
        guard active?.id == id else { return }
        let failure =
            error as? BluetoothFailure
            ?? BluetoothFailure(.writeFailed, detail: String(describing: error))
        finishActive(.failure(failure), id: id)
    }

    private func timedOut(id: UUID) {
        guard active?.id == id else { return }
        finishActive(
            .failure(BluetoothFailure(.responseTimeout, detail: "No matching response before timeout")),
            id: id
        )
    }

    private func cancel(id: UUID) {
        if active?.id == id {
            finishActive(.failure(CancellationError()), id: id)
            return
        }
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let item = pending.remove(at: index)
        item.continuation.resume(throwing: CancellationError())
    }

    private func finishActive(
        _ result: Result<Data, any Error>,
        id: UUID?,
        startNext: Bool = true
    ) {
        guard let item = active, id == item.id else { return }
        active = nil
        writeTask?.cancel()
        timeoutTask?.cancel()
        writeTask = nil
        timeoutTask = nil
        decoder.reset()
        item.continuation.resume(with: result)
        if startNext { pump() }
    }
}
