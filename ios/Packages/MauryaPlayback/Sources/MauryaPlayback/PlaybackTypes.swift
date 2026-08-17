import Dispatch
import Foundation
import MauryaEffects
import MauryaProtocol

public enum PlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case running
    case paused
    case reconnecting
    case stopping
    case failed(String)
}

public enum PlaybackFrameMode: Equatable, Sendable {
    case groups
    case pixels
}

public enum PlaybackLifecycle: Equatable, Sendable {
    case foreground
    case inactive
    case background
}

/// Background continuation is deliberately experimental. The default policy
/// pauses and requires an explicit foreground resume.
public enum PlaybackBackgroundPolicy: Equatable, Sendable {
    case stopAndRequireForegroundResume
    case experimentalAudioContinuation(userEnabled: Bool, releaseApproved: Bool)
}

public struct PlaybackConfiguration: Equatable, Sendable {
    public var groupHertz: UInt64
    public var pixelHertz: UInt64
    public var heartbeatIntervalNanoseconds: UInt64
    public var inputWarmupNanoseconds: UInt64
    public var backgroundPolicy: PlaybackBackgroundPolicy

    public init(
        groupHertz: UInt64 = 10,
        pixelHertz: UInt64 = 20,
        heartbeatIntervalNanoseconds: UInt64 = 1_000_000_000,
        inputWarmupNanoseconds: UInt64 = 1_000_000_000,
        backgroundPolicy: PlaybackBackgroundPolicy = .stopAndRequireForegroundResume
    ) {
        precondition(groupHertz > 0 && pixelHertz > 0)
        precondition(heartbeatIntervalNanoseconds > 0 && heartbeatIntervalNanoseconds < 5_000_000_000)
        precondition(inputWarmupNanoseconds <= 10_000_000_000)
        self.groupHertz = groupHertz
        self.pixelHertz = pixelHertz
        self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
        self.inputWarmupNanoseconds = inputWarmupNanoseconds
        self.backgroundPolicy = backgroundPolicy
    }
}

public struct PlaybackDeviceContext: Equatable, Sendable {
    public let capabilities: UInt8
    public let geometry: MauryaProtocol.EffectGeometry

    public init(capabilities: UInt8, geometry: MauryaProtocol.EffectGeometry) {
        self.capabilities = capabilities
        self.geometry = geometry
    }
}

public struct PlaybackMetrics: Equatable, Sendable {
    public internal(set) var beganSessions = 0
    public internal(set) var framesAcknowledged = 0
    public internal(set) var heartbeatsAcknowledged = 0
    public internal(set) var coalescedFrames = 0
    public internal(set) var acknowledgementMismatches = 0
    public internal(set) var transportFailures = 0
    public internal(set) var reconnects = 0
    public internal(set) var firstFrameNanoseconds: UInt64?
    public internal(set) var lastFrameNanoseconds: UInt64?

    public init() {}

    public var measuredFrameHertz: Double? {
        guard framesAcknowledged > 1,
            let firstFrameNanoseconds,
            let lastFrameNanoseconds,
            lastFrameNanoseconds > firstFrameNanoseconds
        else { return nil }
        return Double(framesAcknowledged - 1) * 1_000_000_000 / Double(lastFrameNanoseconds - firstFrameNanoseconds)
    }
}

public enum PlaybackError: Error, Equatable, Sendable {
    case alreadyActive
    case volatileEffectsUnsupported
    case pixelEffectsUnsupported
    case incompatibleGeometry(expectedGroups: Int, expectedPixels: Int, actualGroups: Int, actualPixels: Int)
    case acknowledgementSequenceMismatch(expected: UInt16, actual: UInt16)
    case disconnected
    case staleRequiredInputs([RuntimeInputKey])
}

/// Transports use this typed error so the scheduler can distinguish a link
/// loss (recoverable through capability refresh + BEGIN) from command failure.
public enum PlaybackTransportError: Error, Equatable, Sendable {
    case disconnected
}

public protocol PlaybackClock: Sendable {
    func nowNanoseconds() async -> UInt64
    func sleep(untilNanoseconds deadline: UInt64) async throws
}

public protocol EffectPlaybackTransport: Sendable {
    func refreshDeviceContext() async throws -> PlaybackDeviceContext
    func exchange(_ request: Data) async throws -> Data
    /// Queues END if possible and returns promptly. Failure is intentionally ignored.
    func sendBestEffort(_ request: Data) async
}

public protocol PlaybackInputSource: Sendable {
    func prepare(requiredInputs: Set<RuntimeInputKey>) async throws
    func snapshot(atNanoseconds: UInt64) async -> EffectRuntimeSnapshot
    func stop() async
}

public struct EmptyPlaybackInputSource: PlaybackInputSource {
    public init() {}
    public func prepare(requiredInputs: Set<RuntimeInputKey>) async throws {}
    public func snapshot(atNanoseconds: UInt64) async -> EffectRuntimeSnapshot { .empty }
    public func stop() async {}
}

public struct ContinuousPlaybackClock: PlaybackClock {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public func sleep(untilNanoseconds deadline: UInt64) async throws {
        let now = nowNanoseconds()
        guard deadline > now else { return }
        try await Task.sleep(for: .nanoseconds(Int64(clamping: deadline - now)))
    }
}
