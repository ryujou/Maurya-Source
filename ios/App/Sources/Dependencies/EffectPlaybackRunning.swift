import MauryaEffects
import MauryaPlayback

protocol EffectPlaybackRunning: Sendable {
    func state() async -> PlaybackState
    func run(compiled: CompiledEffect, initialGroups: [MauryaEffects.EffectGroupState], unitID: UInt8) async throws
    func pause() async
    func resume() async
    func stop() async
    func connectionLost() async
    func lifecycleChanged(_ lifecycle: PlaybackLifecycle) async
    func resumeAfterForeground() async
}

extension EffectPlaybackActor: EffectPlaybackRunning {}
