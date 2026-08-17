import Foundation
import MauryaProtocol
import Testing

@testable import MauryaBluetooth

struct BluetoothTransactionQueueTests {
    @Test("A fragmented matching notification completes exactly one transaction")
    func fragmentedResponseCompletesTransaction() async throws {
        let writes = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingOldest(4))
        let queue = try BluetoothTransactionQueue(maximumPendingCount: 4) { request, _ in
            writes.continuation.yield(request)
        }
        let generation = ConnectionGeneration(rawValue: 1)
        let request = ModbusRequest.writeSingleRegister(unitID: 1, register: 0x20, value: 0x1234)

        let transaction = Task {
            try await queue.transact(request, generation: generation, timeout: .seconds(2))
        }
        var iterator = writes.stream.makeAsyncIterator()
        let written = await iterator.next()
        #expect(written == request)

        await queue.receive(Data(request.prefix(3)), generation: generation)
        await queue.receive(Data(request.dropFirst(3)), generation: generation)
        let response = try await transaction.value
        #expect(response == request)
        await queue.close()
        writes.continuation.finish()
    }

    @Test("A stale connection generation cannot complete the active transaction")
    func staleGenerationCannotComplete() async throws {
        let writes = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingOldest(2))
        let queue = try BluetoothTransactionQueue(maximumPendingCount: 2) { request, _ in
            writes.continuation.yield(request)
        }
        let generation = ConnectionGeneration(rawValue: 9)
        let request = ModbusRequest.writeSingleRegister(unitID: 1, register: 2, value: 3)
        let transaction = Task {
            try await queue.transact(request, generation: generation, timeout: .seconds(2))
        }
        var iterator = writes.stream.makeAsyncIterator()
        _ = await iterator.next()

        await queue.receive(request, generation: .init(rawValue: 8))
        #expect(await queue.pendingCount == 1)
        await queue.receive(request, generation: generation)
        #expect(try await transaction.value == request)
        await queue.close()
        writes.continuation.finish()
    }

    @Test("Bounded queue rejects excess work and cancellation cleans the active item")
    func boundedAndCancellable() async throws {
        let writes = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingOldest(2))
        let gate = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        let queue = try BluetoothTransactionQueue(maximumPendingCount: 1) { request, _ in
            writes.continuation.yield(request)
            for await _ in gate.stream { return }
            try Task.checkCancellation()
        }
        let generation = ConnectionGeneration(rawValue: 1)
        let firstRequest = ModbusRequest.writeSingleRegister(unitID: 1, register: 1, value: 1)
        let secondRequest = ModbusRequest.writeSingleRegister(unitID: 1, register: 2, value: 2)

        let first = Task {
            try await queue.transact(firstRequest, generation: generation, timeout: .seconds(2))
        }
        var iterator = writes.stream.makeAsyncIterator()
        _ = await iterator.next()

        do {
            _ = try await queue.transact(secondRequest, generation: generation, timeout: .seconds(2))
            Issue.record("The bounded queue accepted excess work")
        } catch let failure as BluetoothFailure {
            #expect(failure.code == .queueFull)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        first.cancel()
        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        #expect(await queue.pendingCount == 0)
        gate.continuation.finish()
        writes.continuation.finish()
        await queue.close()
    }

    @Test("Response timeout completes once and releases queue capacity")
    func responseTimeoutCleansActiveItem() async throws {
        let queue = try BluetoothTransactionQueue(maximumPendingCount: 1) { _, _ in }
        let request = ModbusRequest.writeSingleRegister(unitID: 1, register: 7, value: 8)

        do {
            _ = try await queue.transact(
                request,
                generation: .init(rawValue: 1),
                timeout: .zero
            )
            Issue.record("The transaction unexpectedly completed without a response")
        } catch let failure as BluetoothFailure {
            #expect(failure.code == .responseTimeout)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await queue.pendingCount == 0)
        await queue.close()
    }
}
