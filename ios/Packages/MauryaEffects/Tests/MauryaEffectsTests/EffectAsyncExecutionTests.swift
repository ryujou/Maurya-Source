import Foundation
import Testing
import os

@testable import MauryaEffects

struct EffectAsyncExecutionTests {
    @Test func cancelledStructuredCompilerChildReturnsTypedError() async {
        let result = await withTaskGroup(of: EffectAsyncExecutionError?.self) { group in
            group.addTask {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try await EffectAsyncCompiler.compileScript(Self.source)
                    return nil
                } catch let error as EffectAsyncExecutionError {
                    return error
                } catch {
                    Issue.record("Unexpected error: \(error)")
                    return nil
                }
            }
            return await group.next() ?? nil
        }
        #expect(result == .cancelled)
    }

    @Test func compilerUsesImmediateMonotonicDeadlineWithoutSleeping() async {
        let expired = ContinuousClock().now
        await #expect(throws: EffectAsyncExecutionError.deadlineExceeded) {
            try await EffectAsyncCompiler.compileScript(Self.source, deadline: expired)
        }
    }

    @Test func cancelledInterpreterCallIsTypedAndTransactional() async throws {
        let compiled = try EffectScriptCompiler.compile(Self.source)
        let interpreter = try EffectAsyncInterpreter(compiled, initialGroups: groups())
        let result = await withTaskGroup(of: EffectAsyncExecutionError?.self) { group in
            group.addTask {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try await interpreter.frame(at: 100)
                    return nil
                } catch let error as EffectAsyncExecutionError {
                    return error
                } catch {
                    Issue.record("Unexpected error: \(error)")
                    return nil
                }
            }
            return await group.next() ?? nil
        }
        #expect(result == .cancelled)

        let recovered = try await interpreter.frame(at: 100)
        var synchronous = try EffectInterpreter(compiled, initialGroups: groups())
        #expect(recovered == (try synchronous.frame(at: 100)))
    }

    @Test func interpreterUsesImmediateMonotonicDeadlineWithoutSleeping() async throws {
        let compiled = try EffectScriptCompiler.compile(Self.source)
        let interpreter = try EffectAsyncInterpreter(compiled, initialGroups: groups())
        let expired = ContinuousClock().now
        await #expect(throws: EffectAsyncExecutionError.deadlineExceeded) {
            try await interpreter.frame(at: 100, deadline: expired)
        }
    }

    @Test func internalCompilerAndVMCheckMoreThanEntryBoundary() throws {
        let compilerCounter = CheckpointCounter()
        _ = try EffectScriptCompiler.compile(Self.source) { try compilerCounter.hit() }
        #expect(compilerCounter.count > 10)

        let compiled = try EffectScriptCompiler.compile(Self.loopSource)
        var interpreter = try EffectInterpreter(compiled, initialGroups: groups())
        let interpreterCounter = CheckpointCounter()
        _ = try interpreter.frame(at: 500, snapshot: .empty) { try interpreterCounter.hit() }
        #expect(interpreterCounter.count > 20)
    }

    private static let source = ##"effect "async" { let value = 0; repeat(4) { value += 1; all.hsv(value * 60, 255, 255); wait(50ms); } }"##
    private static let loopSource =
        ##"fn colour(number h): color { return hsv(h,255,255); } effect "vm" { for (i from 1 to 7 step 1) { group(i).color(colour(i * 30)); wait(50ms); } }"##

    private func groups() -> [EffectGroupState] { (0..<EffectGeometry.groupCount).map { _ in EffectGroupState() } }
}

private final class CheckpointCounter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)
    var count: Int { state.withLock { $0 } }
    func hit() throws { state.withLock { $0 += 1 } }
}
