import MauryaAnalysis
import MauryaEffects
import MauryaPlayback

actor AnalysisPlaybackInputSource: PlaybackInputSource {
    private let hub: AnalysisInputHub
    private let motion: CoreMotionInputProvider
    private let audio: AppleAudioInputProvider

    init(hub: AnalysisInputHub = AnalysisInputHub()) {
        self.hub = hub
        motion = CoreMotionInputProvider(hub: hub)
        audio = AppleAudioInputProvider(hub: hub)
    }

    func prepare(requiredInputs: Set<RuntimeInputKey>) async throws {
        await stop()
        await hub.setRequiredInputs(requiredInputs, at: AnalysisClock.monotonicMilliseconds())
        let audioInputs = requiredInputs.intersection(AppleAudioInputProvider.inputKeys)
        if audioInputs.isEmpty == false { try await audio.start() }
        let motionInputs = requiredInputs.subtracting(AppleAudioInputProvider.inputKeys)
        if motionInputs.isEmpty == false { await motion.start(required: motionInputs) }
    }

    func snapshot(atNanoseconds: UInt64) async -> EffectRuntimeSnapshot {
        await hub.snapshot(at: Int64(clamping: atNanoseconds / 1_000_000)).effectRuntimeSnapshot()
    }

    func stop() async {
        await audio.stop()
        await motion.stop()
    }
}
