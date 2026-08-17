import Foundation
import os

/// Fixed-capacity single-producer/single-consumer PCM storage.
///
/// The producer is an audio realtime callback, so it must not wait. It uses a
/// non-blocking lock attempt and drops the complete incoming chunk on
/// contention. Consumer and lifecycle calls run outside the realtime callback
/// and may take the lock normally.
final class PCMRingBuffer: Sendable {
    /// `OSAllocatedUnfairLock` requires a `@Sendable` critical-region closure.
    /// This wrapper is safe only because `append` executes that closure
    /// synchronously and never stores or returns the pointer; AVAudioPCMBuffer
    /// owns the channel memory for the complete callback invocation.
    private struct RealtimeSource: @unchecked Sendable {
        let pointer: UnsafePointer<Float>
        let count: Int
    }

    /// Same synchronous-lifetime boundary as `RealtimeSource`, for the native
    /// noninterleaved channel table owned by AVAudioPCMBuffer.
    private struct RealtimeChannels: @unchecked Sendable {
        let pointer: UnsafePointer<UnsafeMutablePointer<Float>>
        let channelCount: Int
        let frameCount: Int
    }

    private struct State: Sendable {
        var storage: [Float]
        var readIndex = 0
        var writeIndex = 0
        var count = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(capacity: Int) {
        state = OSAllocatedUnfairLock(
            initialState: State(
                storage: Array(repeating: 0, count: max(1, capacity))
            ))
    }

    @discardableResult
    func append(_ source: UnsafePointer<Float>, count sourceCount: Int) -> Bool {
        guard sourceCount >= 0 else { return false }
        let realtimeSource = RealtimeSource(pointer: source, count: sourceCount)
        return state.withLockIfAvailable { state in
            for index in 0..<realtimeSource.count {
                if state.count == state.storage.count {
                    state.readIndex = (state.readIndex + 1) % state.storage.count
                    state.count -= 1
                }
                state.storage[state.writeIndex] = realtimeSource.pointer[index]
                state.writeIndex = (state.writeIndex + 1) % state.storage.count
                state.count += 1
            }
            return true
        } ?? false
    }

    @discardableResult
    func appendMono(
        _ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int
    ) -> Bool {
        guard channelCount > 0, frameCount >= 0 else { return false }
        let realtimeChannels = RealtimeChannels(
            pointer: channels,
            channelCount: channelCount,
            frameCount: frameCount
        )
        return state.withLockIfAvailable { state in
            for frame in 0..<realtimeChannels.frameCount {
                var sum: Float = 0
                for channel in 0..<realtimeChannels.channelCount {
                    sum += realtimeChannels.pointer[channel][frame]
                }
                if state.count == state.storage.count {
                    state.readIndex = (state.readIndex + 1) % state.storage.count
                    state.count -= 1
                }
                state.storage[state.writeIndex] = sum / Float(realtimeChannels.channelCount)
                state.writeIndex = (state.writeIndex + 1) % state.storage.count
                state.count += 1
            }
            return true
        } ?? false
    }

    func popFrame() -> [Double]? {
        state.withLock { state in
            guard state.count >= AudioAnalyzer.frameSize else { return nil }
            var result = Array(repeating: 0.0, count: AudioAnalyzer.frameSize)
            for index in result.indices {
                result[index] = Double(state.storage[state.readIndex])
                state.readIndex = (state.readIndex + 1) % state.storage.count
                state.count -= 1
            }
            return result
        }
    }

    func pop(upTo maximumCount: Int) -> [Double]? {
        state.withLock { state in
            let resultCount = min(maximumCount, state.count)
            guard resultCount > 0 else { return nil }
            var result = Array(repeating: 0.0, count: resultCount)
            for index in result.indices {
                result[index] = Double(state.storage[state.readIndex])
                state.readIndex = (state.readIndex + 1) % state.storage.count
                state.count -= 1
            }
            return result
        }
    }

    func clear() {
        state.withLock { state in
            state.readIndex = 0
            state.writeIndex = 0
            state.count = 0
        }
    }
}
