import Dispatch
import Foundation
import MauryaEffects
import MauryaPlayback
import MauryaProtocol
import Testing

actor VirtualClock: PlaybackClock {
    private var now: UInt64 = 0

    func nowNanoseconds() -> UInt64 { now }

    func sleep(untilNanoseconds deadline: UInt64) throws {
        try Task.checkCancellation()
        now = max(now, deadline)
    }

    func advance(by nanoseconds: UInt64) { now += nanoseconds }
}

actor FakeTransport: EffectPlaybackTransport {
    private let clock: VirtualClock
    private let latency: UInt64
    private let mismatchSequence: Bool
    private let reconnectLatency: UInt64
    private var disconnectNextFrame: Bool
    private var delayNextBegin = false
    private var nextSession: UInt32 = 0x1234_0000
    private(set) var requests: [Data] = []
    private(set) var bestEffortRequests: [Data] = []

    init(
        clock: VirtualClock,
        latency: UInt64 = 0,
        mismatchSequence: Bool = false,
        disconnectNextFrame: Bool = false,
        reconnectLatency: UInt64 = 0
    ) {
        self.clock = clock
        self.latency = latency
        self.mismatchSequence = mismatchSequence
        self.disconnectNextFrame = disconnectNextFrame
        self.reconnectLatency = reconnectLatency
    }

    func refreshDeviceContext() throws -> PlaybackDeviceContext {
        PlaybackDeviceContext(
            capabilities: EffectProtocolCodec.volatileEffectCapability | EffectProtocolCodec.pixelEffectCapability,
            geometry: .legacyFirmwareFallback
        )
    }

    func exchange(_ request: Data) async throws -> Data {
        requests.append(request)
        if latency > 0 { await clock.advance(by: latency) }
        let command = request[request.startIndex + 3]
        switch command {
        case EffectCommand.begin.rawValue:
            if delayNextBegin {
                delayNextBegin = false
                await clock.advance(by: reconnectLatency)
            }
            nextSession &+= 1
            return try ModbusRequest.vendor(
                unitID: 1,
                payload: Data([
                    command, 0, 0x30, 4,
                    UInt8(truncatingIfNeeded: nextSession),
                    UInt8(truncatingIfNeeded: nextSession >> 8),
                    UInt8(truncatingIfNeeded: nextSession >> 16),
                    UInt8(truncatingIfNeeded: nextSession >> 24),
                ])
            )
        case EffectCommand.groupFrame.rawValue, EffectCommand.pixelFrame.rawValue:
            if disconnectNextFrame {
                disconnectNextFrame = false
                delayNextBegin = true
                throw PlaybackTransportError.disconnected
            }
            var sequence = UInt16(request[request.startIndex + 8]) | UInt16(request[request.startIndex + 9]) << 8
            if mismatchSequence { sequence &+= 1 }
            return try ModbusRequest.vendor(
                unitID: 1,
                payload: Data([
                    command, 0, 0x31, 2,
                    UInt8(truncatingIfNeeded: sequence),
                    UInt8(truncatingIfNeeded: sequence >> 8),
                ])
            )
        case EffectCommand.heartbeat.rawValue:
            return try ModbusRequest.vendor(unitID: 1, payload: Data([command, 0]))
        default:
            throw TestTransportError.unexpectedCommand(command)
        }
    }

    func sendBestEffort(_ request: Data) { bestEffortRequests.append(request) }

    func requests(for command: EffectCommand) -> [Data] {
        requests.filter { $0[$0.startIndex + 3] == command.rawValue }
    }

    func bestEffortCount() -> Int { bestEffortRequests.count }
}

actor StaleInputSource: PlaybackInputSource {
    private(set) var requested: Set<RuntimeInputKey> = []
    private(set) var snapshotTimes: [UInt64] = []
    private(set) var stopCount = 0

    func prepare(requiredInputs: Set<RuntimeInputKey>) {
        requested = requiredInputs
    }

    func snapshot(atNanoseconds: UInt64) -> EffectRuntimeSnapshot {
        snapshotTimes.append(atNanoseconds)
        return EffectRuntimeSnapshot(
            capturedAtMilliseconds: Int64(clamping: atNanoseconds / 1_000_000),
            values: [.audioLevel: .number(0.5)],
            available: [.audioLevel],
            updatedAtMilliseconds: [.audioLevel: 0]
        )
    }

    func stop() { stopCount += 1 }
}

actor ReconnectStaleInputSource: PlaybackInputSource {
    private(set) var prepareCount = 0
    private(set) var snapshotTimes: [UInt64] = []

    func prepare(requiredInputs: Set<RuntimeInputKey>) { prepareCount += 1 }

    func snapshot(atNanoseconds: UInt64) -> EffectRuntimeSnapshot {
        snapshotTimes.append(atNanoseconds)
        return EffectRuntimeSnapshot(
            capturedAtMilliseconds: Int64(clamping: atNanoseconds / 1_000_000),
            values: [.audioLevel: .number(0.5)],
            available: [.audioLevel],
            updatedAtMilliseconds: [.audioLevel: 0]
        )
    }

    func stop() {}
}

enum TestTransportError: Error {
    case unexpectedCommand(UInt8)
}

struct EffectPlaybackActorTests {
    @Test func defaultClockSharesAnalysisMonotonicUptimeDomain() {
        let before = DispatchTime.now().uptimeNanoseconds
        let value = ContinuousPlaybackClock().nowNanoseconds()
        let after = DispatchTime.now().uptimeNanoseconds
        #expect((before...after).contains(value))
    }

    @Test func groupPlaybackUsesTenHertzAbsoluteDeadlinesAndCleansUp() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock)
        let player = EffectPlaybackActor(transport: transport, clock: clock)

        try await player.run(
            compiled: changingGroupProgram(),
            initialGroups: initialGroups()
        )

        let frameRequests = await transport.requests(for: .groupFrame)
        #expect(frameRequests.count == 5)
        #expect(await transport.bestEffortCount() == 1)
        #expect(await player.state() == .idle)
        #expect(await player.metrics().framesAcknowledged == 5)
        #expect(await player.metrics().measuredFrameHertz == 10)
    }

    @Test func finiteProgressDoesNotResendUnchangedWirePayload() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock)
        let player = EffectPlaybackActor(transport: transport, clock: clock)

        try await player.run(
            compiled: finiteProgram(pixel: false, durationMilliseconds: 350),
            initialGroups: initialGroups()
        )

        #expect(await transport.requests(for: .groupFrame).count == 1)
        #expect(await transport.bestEffortCount() == 1)
    }

    @Test func pixelPlaybackUsesExact140ByteFramesAndCoalescesBackpressure() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock, latency: 130_000_000)
        let player = EffectPlaybackActor(transport: transport, clock: clock)

        try await player.run(
            compiled: finiteProgram(pixel: true, durationMilliseconds: 400),
            initialGroups: initialGroups()
        )

        let frames = await transport.requests(for: .pixelFrame)
        #expect(frames.isEmpty == false)
        #expect(frames.allSatisfy { $0.count == 140 })
        #expect(await player.metrics().coalescedFrames > 0)
    }

    @Test func unchangedFramesUseOneSecondHeartbeatBeforeFirmwareTimeout() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock)
        let player = EffectPlaybackActor(transport: transport, clock: clock)

        try await player.run(
            compiled: CompiledEffect(
                operations: [.wait(.number(1_200)), .end()],
                blockCount: 2,
                estimatedDurationMilliseconds: nil
            ),
            initialGroups: initialGroups()
        )

        #expect(await transport.requests(for: .heartbeat).count == 1)
        #expect(await player.metrics().heartbeatsAcknowledged == 1)
    }

    @Test func mismatchedAcknowledgementFailsAndStillQueuesEnd() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock, mismatchSequence: true)
        let player = EffectPlaybackActor(transport: transport, clock: clock)

        await #expect(throws: PlaybackError.acknowledgementSequenceMismatch(expected: 1, actual: 2)) {
            try await player.run(
                compiled: finiteProgram(pixel: false, durationMilliseconds: 100),
                initialGroups: initialGroups()
            )
        }
        #expect(await transport.bestEffortCount() == 1)
        #expect(await player.metrics().acknowledgementMismatches == 1)
    }

    @Test func disconnectRefreshesGeometryAndBeginsANewSession() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock, disconnectNextFrame: true)
        let player = EffectPlaybackActor(transport: transport, clock: clock)

        try await player.run(
            compiled: finiteProgram(pixel: false, durationMilliseconds: 100),
            initialGroups: initialGroups()
        )

        #expect(await transport.requests(for: .begin).count == 2)
        #expect(await player.metrics().beganSessions == 2)
        #expect(await player.metrics().reconnects == 1)
        #expect(await transport.bestEffortCount() == 1)
    }

    @Test func reconnectDelayDoesNotAdvanceEffectTimeline() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(
            clock: clock,
            disconnectNextFrame: true,
            reconnectLatency: 2_000_000_000
        )
        let player = EffectPlaybackActor(transport: transport, clock: clock)
        let compiled = try EffectCompiler.compile(
            operations: [
                .repeatLoop(
                    count: .number(3),
                    body: [
                        .adjustHSV(.all, dh: .number(1), ds: .number(0), dv: .number(0)),
                        .wait(.number(100)),
                    ]
                ),
                .end(),
            ],
            nodeCount: 4
        )

        try await player.run(compiled: compiled, initialGroups: initialGroups())

        let frames = await transport.requests(for: .groupFrame)
        #expect(frames.count >= 2)
        let reconnectedHue =
            Int(frames[1][frames[1].startIndex + 11])
            | Int(frames[1][frames[1].startIndex + 12]) << 8
        #expect(reconnectedHue == 1)
    }

    @Test func reconnectRestartsRequiredInputWarmup() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(
            clock: clock,
            disconnectNextFrame: true,
            reconnectLatency: 2_000_000_000
        )
        let inputs = ReconnectStaleInputSource()
        let player = EffectPlaybackActor(transport: transport, clock: clock, inputs: inputs)
        let compiled = CompiledEffect(
            operations: [.wait(.number(1_500)), .end()],
            blockCount: 2,
            estimatedDurationMilliseconds: 1_500,
            requiredInputs: [.audioLevel]
        )

        await #expect(throws: PlaybackError.staleRequiredInputs([.audioLevel])) {
            try await player.run(compiled: compiled, initialGroups: initialGroups())
        }

        #expect(await inputs.prepareCount == 2)
        let times = await inputs.snapshotTimes
        #expect(times.contains(3_000_000_000))
        #expect(times.last == 3_100_000_000)
    }

    @Test func staleRequiredInputFailsAfterStrictOneSecondWarmupAndCleansUp() async throws {
        let clock = VirtualClock()
        let transport = FakeTransport(clock: clock)
        let inputs = StaleInputSource()
        let player = EffectPlaybackActor(transport: transport, clock: clock, inputs: inputs)
        let compiled = CompiledEffect(
            operations: [.wait(.number(1_500)), .end()],
            blockCount: 2,
            estimatedDurationMilliseconds: 1_500,
            requiredInputs: [.audioLevel]
        )

        await #expect(throws: PlaybackError.staleRequiredInputs([.audioLevel])) {
            try await player.run(compiled: compiled, initialGroups: initialGroups())
        }

        let times = await inputs.snapshotTimes
        #expect(times.contains(1_000_000_000), "Exactly 1 second is still inside Android's warm-up boundary.")
        #expect(times.last == 1_100_000_000)
        #expect(await inputs.requested == [.audioLevel])
        #expect(await inputs.stopCount == 1)
        #expect(await transport.bestEffortCount() == 1)
        guard case .failed = await player.state() else {
            Issue.record("A stale required input must leave playback in a terminal failed state.")
            return
        }
    }
}

private func finiteProgram(pixel: Bool, durationMilliseconds: Int64) -> CompiledEffect {
    CompiledEffect(
        operations: [
            .setColour(pixel ? .allPixels : .all, .colour(EffectColour(hue: 120, saturation: 255, value: 200))),
            .wait(.number(Double(durationMilliseconds))),
            .end(),
        ],
        blockCount: 3,
        estimatedDurationMilliseconds: durationMilliseconds,
        requiresPixelEffect: pixel
    )
}

private func changingGroupProgram() -> CompiledEffect {
    let operations: [EffectOperation] =
        (0..<5).flatMap { index in
            [
                .setHSV(.all, h: .number(Double(index * 30)), s: .number(255), v: .number(200)),
                .wait(.number(100)),
            ]
        } + [.end()]
    return CompiledEffect(
        operations: operations,
        blockCount: operations.count,
        estimatedDurationMilliseconds: 500
    )
}

private func initialGroups() -> [MauryaEffects.EffectGroupState] {
    (0..<MauryaEffects.EffectGeometry.groupCount).map {
        MauryaEffects.EffectGroupState(hue: $0 * 30, saturation: 255, value: 100)
    }
}
