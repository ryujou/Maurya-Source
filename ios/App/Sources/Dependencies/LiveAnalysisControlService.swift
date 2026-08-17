import MauryaAnalysis
import MauryaEffects
import Observation

@MainActor
@Observable
final class LiveAnalysisControlService: AnalysisControlService {
    private(set) var state: AnalysisPresentationState = .idle
    private(set) var snapshot: AnalysisInputSnapshot?
    private(set) var virtualInputsEnabled = false
    private(set) var audioSensitivity = 1.0
    private let hub: AnalysisInputHub
    private let motion: CoreMotionInputProvider
    private let audio: AppleAudioInputProvider
    private var sessionTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?

    init(hub: AnalysisInputHub = AnalysisInputHub()) {
        self.hub = hub
        motion = CoreMotionInputProvider(hub: hub)
        audio = AppleAudioInputProvider(hub: hub)
        snapshotTask = Task(name: "Maurya analysis snapshot observer") { [weak self] in
            let stream = await hub.snapshots(bufferingNewest: 1)
            for await value in stream {
                guard let self else { return }
                snapshot = value
            }
        }
    }

    func start(_ mode: AnalysisMode) {
        stop()
        state = .starting(mode)
        sessionTask = Task(name: "Maurya foreground analysis") { [weak self] in
            guard let self else { return }
            do {
                switch mode {
                case .motion:
                    let inputs: Set<RuntimeInputKey> = [.sensorAccelX, .sensorAccelY, .sensorAccelZ, .sensorMotion, .sensorShake]
                    await hub.setRequiredInputs(inputs, at: AnalysisClock.monotonicMilliseconds())
                    await motion.start(required: inputs, hertz: 30)
                case .audio:
                    await hub.setRequiredInputs(AppleAudioInputProvider.inputKeys, at: AnalysisClock.monotonicMilliseconds())
                    try await audio.start()
                case .virtual:
                    return
                }
                guard Task.isCancelled == false else { throw CancellationError() }
                state = .running(mode)
                try await Task.sleep(for: .seconds(86_400 * 365))
            } catch is CancellationError {
                await stopProviders()
            } catch AudioInputError.permissionDenied {
                state = .unavailable("analysis.microphone.denied")
                await stopProviders()
            } catch {
                state = .failed(String(describing: error))
                await stopProviders()
            }
        }
    }

    func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        state = .idle
    }

    func setVirtualInputsEnabled(_ enabled: Bool) {
        guard enabled != virtualInputsEnabled else { return }
        stop()
        virtualInputsEnabled = enabled
        Task {
            await stopProviders()
            let now = AnalysisClock.monotonicMilliseconds()
            if enabled {
                let inputs: Set<RuntimeInputKey> = [
                    .sensorMotion, .sensorRoll, .sensorLight, .audioLevel, .audioBPM,
                ]
                await hub.setRequiredInputs(inputs, at: now)
                await hub.setVirtualInput(.sensorMotion, value: .number(0), at: now)
                await hub.setVirtualInput(.sensorRoll, value: .number(0), at: now)
                await hub.setVirtualInput(.sensorLight, value: .number(0), at: now)
                await hub.setVirtualInput(.audioLevel, value: .number(0), at: now)
                await hub.setVirtualInput(.audioBPM, value: .number(120), at: now)
                state = .running(.virtual)
            } else {
                await hub.clearVirtualInputs(at: now)
                await hub.setRequiredInputs([], at: now)
                state = .idle
            }
        }
    }

    func setVirtualInput(_ key: RuntimeInputKey, value: Double) {
        guard virtualInputsEnabled else { return }
        Task {
            await hub.setVirtualInput(
                key,
                value: .number(value),
                at: AnalysisClock.monotonicMilliseconds()
            )
        }
    }

    func zeroAttitude() { Task { await motion.zeroAttitude() } }

    func setAudioSensitivity(_ value: Double) {
        audioSensitivity = min(max(value, 0.25), 4)
        let sensitivity = audioSensitivity
        Task { await audio.setSensitivity(sensitivity) }
    }

    private func stopProviders() async {
        await audio.stop()
        await motion.stop()
    }
}

@MainActor
@Observable
final class FakeAnalysisControlService: AnalysisControlService {
    var state: AnalysisPresentationState
    var snapshot: AnalysisInputSnapshot?
    var virtualInputsEnabled = false
    var audioSensitivity = 1.0
    init(state: AnalysisPresentationState = .idle, snapshot: AnalysisInputSnapshot? = nil) {
        self.state = state
        self.snapshot = snapshot
    }
    func start(_ mode: AnalysisMode) { state = .running(mode) }
    func stop() { state = .idle }
    func setVirtualInputsEnabled(_ enabled: Bool) {
        virtualInputsEnabled = enabled
        state = enabled ? .running(.virtual) : .idle
    }
    func setVirtualInput(_ key: RuntimeInputKey, value: Double) {}
    func zeroAttitude() {}
    func setAudioSensitivity(_ value: Double) { audioSensitivity = value }
}
