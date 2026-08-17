import Foundation
import MauryaEffects
import MauryaProtocol

public actor EffectPlaybackActor {
    private let transport: any EffectPlaybackTransport
    private let clock: any PlaybackClock
    private let inputs: any PlaybackInputSource
    private let configuration: PlaybackConfiguration

    private var stateValue: PlaybackState = .idle
    private var metricsValue = PlaybackMetrics()
    private var stopRequested = false
    private var manuallyPaused = false
    private var lifecyclePaused = false
    private var disconnected = false
    private var disconnectedAtNanoseconds: UInt64?
    private var sessionID: UInt32?
    private var unitID: UInt8 = 1
    private var requiredInputs: Set<RuntimeInputKey> = []
    private var allowsExperimentalBackground = false

    public init(
        transport: any EffectPlaybackTransport,
        clock: any PlaybackClock = ContinuousPlaybackClock(),
        inputs: any PlaybackInputSource = EmptyPlaybackInputSource(),
        configuration: PlaybackConfiguration = PlaybackConfiguration()
    ) {
        self.transport = transport
        self.clock = clock
        self.inputs = inputs
        self.configuration = configuration
    }

    public func state() -> PlaybackState { stateValue }
    public func metrics() -> PlaybackMetrics { metricsValue }

    /// Runs playback in the caller's structured task. Cancelling the caller
    /// cancels the clock wait and proceeds through the same bounded cleanup.
    public func run(
        compiled: CompiledEffect,
        initialGroups: [MauryaEffects.EffectGroupState],
        unitID: UInt8 = 1
    ) async throws {
        guard stateValue == .idle || isTerminalFailure else { throw PlaybackError.alreadyActive }
        resetRunState(unitID: unitID)
        stateValue = .preparing

        do {
            try await inputs.prepare(requiredInputs: compiled.requiredInputs)
            requiredInputs = compiled.requiredInputs
            allowsExperimentalBackground = experimentalBackgroundAllowed(for: compiled)
            var interpreter = try EffectInterpreter(compiled, initialGroups: initialGroups)
            var context = try await transport.refreshDeviceContext()
            try validate(compiled: compiled, context: context)
            sessionID = try await begin()

            let mode: PlaybackFrameMode = compiled.requiresPixelEffect ? .pixels : .groups
            let interval = frameInterval(for: mode)
            let startedAt = await clock.nowNanoseconds()
            var inputWarmupStartedAt = startedAt
            var pausedAt: UInt64?
            var pausedNanoseconds: UInt64 = 0
            var nextFrameDeadline = startedAt
            var lastActivity = startedAt
            var sequence: UInt16 = 0
            var previousGroups: [MauryaEffects.EffectGroupState]?
            var previousPixels: [MauryaEffects.EffectRGB]?
            stateValue = .running

            while true {
                try Task.checkCancellation()
                if stopRequested { break }

                if disconnected {
                    stateValue = .reconnecting
                    let reconnectStartedAt: UInt64
                    if let disconnectedAtNanoseconds {
                        reconnectStartedAt = disconnectedAtNanoseconds
                    } else {
                        reconnectStartedAt = await clock.nowNanoseconds()
                    }
                    try await inputs.prepare(requiredInputs: requiredInputs)
                    context = try await transport.refreshDeviceContext()
                    try validate(compiled: compiled, context: context)
                    sessionID = try await begin()
                    let reconnectedAt = await clock.nowNanoseconds()
                    if pausedAt == nil {
                        pausedNanoseconds = addingClamped(
                            pausedNanoseconds,
                            reconnectedAt >= reconnectStartedAt ? reconnectedAt - reconnectStartedAt : 0
                        )
                    }
                    inputWarmupStartedAt = reconnectedAt
                    disconnectedAtNanoseconds = nil
                    disconnected = false
                    metricsValue.reconnects += 1
                    nextFrameDeadline = reconnectedAt
                    // A new firmware session must receive a complete current
                    // payload even if the logical output did not change while
                    // the transport was disconnected.
                    previousGroups = nil
                    previousPixels = nil
                    stateValue = manuallyPaused || lifecyclePaused ? .paused : .running
                }

                if manuallyPaused || lifecyclePaused {
                    let now = await clock.nowNanoseconds()
                    if pausedAt == nil { pausedAt = now }
                    stateValue = .paused

                    if lifecyclePaused && !allowsExperimentalBackground {
                        try await clock.sleep(untilNanoseconds: now + min(interval, 100_000_000))
                        continue
                    }
                    if now >= lastActivity + configuration.heartbeatIntervalNanoseconds {
                        try await heartbeat()
                        lastActivity = await clock.nowNanoseconds()
                    }
                    try await clock.sleep(
                        untilNanoseconds: min(
                            lastActivity + configuration.heartbeatIntervalNanoseconds,
                            now + 100_000_000
                        )
                    )
                    continue
                }

                if let pausedAt {
                    let now = await clock.nowNanoseconds()
                    pausedNanoseconds = addingClamped(pausedNanoseconds, now >= pausedAt ? now - pausedAt : 0)
                    nextFrameDeadline = now
                }
                pausedAt = nil
                stateValue = .running

                let now = await clock.nowNanoseconds()
                if now > nextFrameDeadline + interval {
                    let skipped = (now - nextFrameDeadline) / interval
                    metricsValue.coalescedFrames += Int(skipped)
                    nextFrameDeadline += skipped * interval
                }

                let wallElapsed = now >= startedAt ? now - startedAt : 0
                let elapsed = wallElapsed >= pausedNanoseconds ? wallElapsed - pausedNanoseconds : 0
                let snapshot = await inputs.snapshot(atNanoseconds: now)
                let staleInputs =
                    requiredInputs
                    .filter {
                        snapshot.isStale(
                            $0,
                            nowMilliseconds: Int64(clamping: now / 1_000_000)
                        )
                    }
                    .sorted { $0.rawValue < $1.rawValue }
                let warmupElapsed = now >= inputWarmupStartedAt ? now - inputWarmupStartedAt : 0
                if staleInputs.isEmpty == false,
                    warmupElapsed > configuration.inputWarmupNanoseconds
                {
                    throw PlaybackError.staleRequiredInputs(staleInputs)
                }
                let frame = try interpreter.frame(
                    at: Int64(clamping: elapsed / 1_000_000),
                    snapshot: snapshot
                )

                let outputChanged =
                    switch mode {
                    case .groups: frame.groups != previousGroups
                    case .pixels: frame.pixels != previousPixels
                    }
                if outputChanged {
                    sequence &+= 1
                    do {
                        try await send(frame: frame, mode: mode, sequence: sequence, context: context)
                    } catch PlaybackTransportError.disconnected {
                        await markDisconnected()
                        await inputs.stop()
                        continue
                    }
                    let sentAt = await clock.nowNanoseconds()
                    recordFrame(at: sentAt)
                    lastActivity = sentAt
                    previousGroups = frame.groups
                    previousPixels = frame.pixels
                } else if now >= lastActivity + configuration.heartbeatIntervalNanoseconds {
                    do {
                        try await heartbeat()
                    } catch PlaybackTransportError.disconnected {
                        await markDisconnected()
                        await inputs.stop()
                        continue
                    }
                    lastActivity = await clock.nowNanoseconds()
                }

                if frame.finished { break }
                nextFrameDeadline += interval
                try await clock.sleep(untilNanoseconds: nextFrameDeadline)
            }

            await cleanup(finalState: .idle)
        } catch is CancellationError {
            await cleanup(finalState: .idle)
            throw CancellationError()
        } catch {
            metricsValue.transportFailures += 1
            await cleanup(finalState: .failed(String(describing: error)))
            throw error
        }
    }

    public func pause() { manuallyPaused = true }

    public func resume() {
        manuallyPaused = false
    }

    public func stop() { stopRequested = true }

    public func connectionLost() async {
        await markDisconnected()
        await inputs.stop()
    }

    public func lifecycleChanged(_ lifecycle: PlaybackLifecycle) async {
        switch lifecycle {
        case .foreground:
            break
        case .inactive, .background:
            guard allowsExperimentalBackground == false else { return }
            lifecyclePaused = true
            let endingSession = sessionID
            sessionID = nil
            stateValue = .paused
            await inputs.stop()
            if let endingSession,
                let request = try? EffectProtocolCodec.endRequest(unitID: unitID, sessionID: endingSession)
            {
                await transport.sendBestEffort(request)
            }
        }
    }

    /// Foreground return never silently resumes user-visible output.
    public func resumeAfterForeground() {
        lifecyclePaused = false
        disconnected = true
    }

    private var isTerminalFailure: Bool {
        if case .failed = stateValue { return true }
        return false
    }

    private func resetRunState(unitID: UInt8) {
        self.unitID = unitID
        metricsValue = PlaybackMetrics()
        stopRequested = false
        manuallyPaused = false
        lifecyclePaused = false
        disconnected = false
        disconnectedAtNanoseconds = nil
        sessionID = nil
        requiredInputs = []
        allowsExperimentalBackground = false
    }

    private func frameInterval(for mode: PlaybackFrameMode) -> UInt64 {
        1_000_000_000 / (mode == .pixels ? configuration.pixelHertz : configuration.groupHertz)
    }

    private func markDisconnected() async {
        if disconnectedAtNanoseconds == nil {
            disconnectedAtNanoseconds = await clock.nowNanoseconds()
        }
        disconnected = true
        sessionID = nil
        stateValue = .reconnecting
    }

    private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }

    private func validate(compiled: CompiledEffect, context: PlaybackDeviceContext) throws {
        guard context.capabilities & EffectProtocolCodec.volatileEffectCapability != 0 else {
            throw PlaybackError.volatileEffectsUnsupported
        }
        if compiled.requiresPixelEffect,
            context.capabilities & EffectProtocolCodec.pixelEffectCapability == 0
        {
            throw PlaybackError.pixelEffectsUnsupported
        }
        let expectedGroups = MauryaEffects.EffectGeometry.groupCount
        let expectedPixels = MauryaEffects.EffectGeometry.pixelCount
        guard Int(context.geometry.groupCount) == expectedGroups,
            context.geometry.pixelCount == expectedPixels
        else {
            throw PlaybackError.incompatibleGeometry(
                expectedGroups: expectedGroups,
                expectedPixels: expectedPixels,
                actualGroups: Int(context.geometry.groupCount),
                actualPixels: context.geometry.pixelCount
            )
        }
    }

    private func begin() async throws -> UInt32 {
        let request = try EffectProtocolCodec.beginRequest(unitID: unitID)
        let response = try await transport.exchange(request)
        let id = try EffectProtocolCodec.parseBeginResponse(response, expectedUnitID: unitID)
        metricsValue.beganSessions += 1
        return id
    }

    private func send(
        frame: EffectFrame,
        mode: PlaybackFrameMode,
        sequence: UInt16,
        context: PlaybackDeviceContext
    ) async throws {
        guard let sessionID else { throw PlaybackError.disconnected }
        let request: Data
        let command: EffectCommand
        switch mode {
        case .groups:
            request = try EffectProtocolCodec.groupFrameRequest(
                unitID: unitID,
                sessionID: sessionID,
                sequence: sequence,
                groups: try frame.groups.map(protocolGroup),
                geometry: context.geometry
            )
            command = .groupFrame
        case .pixels:
            guard let pixels = frame.pixels else { throw PlaybackError.pixelEffectsUnsupported }
            request = try EffectProtocolCodec.pixelFrameRequest(
                unitID: unitID,
                sessionID: sessionID,
                sequence: sequence,
                pixels: pixels.map {
                    MauryaProtocol.EffectRGB(
                        red: UInt8(clamping: $0.red),
                        green: UInt8(clamping: $0.green),
                        blue: UInt8(clamping: $0.blue)
                    )
                },
                geometry: context.geometry
            )
            command = .pixelFrame
        }
        let raw = try await transport.exchange(request)
        let ack = try EffectProtocolCodec.parseAcknowledgement(raw, command: command, expectedUnitID: unitID)
        let accepted = try EffectProtocolCodec.parseAcceptedSequence(from: ack)
        guard accepted == sequence else {
            metricsValue.acknowledgementMismatches += 1
            throw PlaybackError.acknowledgementSequenceMismatch(expected: sequence, actual: accepted)
        }
    }

    private func heartbeat() async throws {
        guard let sessionID else { throw PlaybackError.disconnected }
        let request = try EffectProtocolCodec.heartbeatRequest(unitID: unitID, sessionID: sessionID)
        let raw = try await transport.exchange(request)
        _ = try EffectProtocolCodec.parseAcknowledgement(raw, command: .heartbeat, expectedUnitID: unitID)
        metricsValue.heartbeatsAcknowledged += 1
    }

    private func protocolGroup(_ group: MauryaEffects.EffectGroupState) throws -> MauryaProtocol.EffectGroupState {
        guard (0...Int(UInt8.max)).contains(group.innerMode),
            (0...359).contains(group.hue),
            (0...Int(UInt8.max)).contains(group.saturation),
            (0...Int(UInt8.max)).contains(group.value),
            (0...Int(UInt8.max)).contains(group.innerParameter)
        else {
            throw EffectRuntimeError.execution(code: .wireGroupOutOfRange)
        }
        return MauryaProtocol.EffectGroupState(
            innerMode: UInt8(group.innerMode),
            hue: UInt16(group.hue),
            saturation: UInt8(group.saturation),
            value: UInt8(group.value),
            innerParameter: UInt8(group.innerParameter)
        )
    }

    private func recordFrame(at now: UInt64) {
        metricsValue.framesAcknowledged += 1
        if metricsValue.firstFrameNanoseconds == nil { metricsValue.firstFrameNanoseconds = now }
        metricsValue.lastFrameNanoseconds = now
    }

    private func experimentalBackgroundAllowed(for compiled: CompiledEffect) -> Bool {
        guard compiled.requiredInputs.contains(where: { $0.rawValue.hasPrefix("AUDIO_") }) else { return false }
        if case let .experimentalAudioContinuation(userEnabled, releaseApproved) = configuration.backgroundPolicy {
            return userEnabled && releaseApproved
        }
        return false
    }

    private func cleanup(finalState: PlaybackState) async {
        stateValue = .stopping
        let endingSession = sessionID
        sessionID = nil
        await inputs.stop()
        if let endingSession,
            let request = try? EffectProtocolCodec.endRequest(unitID: unitID, sessionID: endingSession)
        {
            await transport.sendBestEffort(request)
        }
        stateValue = finalState
    }
}
