import Foundation
import MauryaAnalysis
import MauryaEffects
import MauryaPlayback
import Observation

@MainActor
@Observable
final class LivePlaybackControlService: PlaybackControlService {
    typealias ProgramProvider = @MainActor () throws -> MauryaEffects.CompiledEffect
    typealias ContextProvider = @MainActor () -> DevicePlaybackContext?
    typealias InputSourceProvider = @MainActor () -> AnalysisPlaybackInputSource
    typealias ActorFactory = @MainActor (DevicePlaybackContext, AnalysisPlaybackInputSource) -> any EffectPlaybackRunning
    typealias LanguageProvider = @MainActor () -> EffectPresentationLanguage

    private(set) var state: PlaybackPresentationState = .idle

    private let programProvider: ProgramProvider
    private let contextProvider: ContextProvider
    private let inputSourceProvider: InputSourceProvider
    private let actorFactory: ActorFactory
    private let languageProvider: LanguageProvider
    private var actor: (any EffectPlaybackRunning)?
    private var playbackTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var generation = 0
    private var isLifecyclePaused = false

    init(
        programProvider: @escaping ProgramProvider,
        contextProvider: @escaping ContextProvider,
        inputSourceProvider: @escaping InputSourceProvider = { AnalysisPlaybackInputSource() },
        languageProvider: @escaping LanguageProvider = { .english },
        actorFactory: @escaping ActorFactory = { context, inputs in
            EffectPlaybackActor(transport: context.transport, inputs: inputs)
        }
    ) {
        self.programProvider = programProvider
        self.contextProvider = contextProvider
        self.inputSourceProvider = inputSourceProvider
        self.languageProvider = languageProvider
        self.actorFactory = actorFactory
    }

    convenience init() {
        self.init(
            programProvider: { throw PlaybackCompositionError.noSelectedProgram },
            contextProvider: { nil }
        )
    }

    @discardableResult
    func start() -> PlaybackPresentationState {
        stop()
        let compiled: MauryaEffects.CompiledEffect
        do {
            compiled = try programProvider()
        } catch {
            state = .failed(EffectErrorPresenter.message(for: error, language: languageProvider()))
            return state
        }
        guard let context = contextProvider() else {
            state = .unavailable("playback.unavailable.connection-and-effect")
            return state
        }

        generation &+= 1
        let runGeneration = generation
        let playback = actorFactory(context, inputSourceProvider())
        actor = playback
        isLifecyclePaused = false
        state = .preparing
        stateTask = Task(name: "Maurya playback state observer") { [weak self] in
            while Task.isCancelled == false {
                if self?.isLifecyclePaused == true {
                    await playback.lifecycleChanged(.background)
                }
                let actorState = await playback.state()
                guard let self, generation == runGeneration else { return }
                consume(actorState)
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        playbackTask = Task(name: "Maurya foreground effect playback") { [weak self] in
            guard let self else { return }
            do {
                try await playback.run(
                    compiled: compiled,
                    initialGroups: context.initialGroups,
                    unitID: context.unitID
                )
                guard generation == runGeneration else { return }
                stateTask?.cancel()
                stateTask = nil
                actor = nil
                playbackTask = nil
                state = .idle
            } catch is CancellationError {
                guard generation == runGeneration else { return }
                stateTask?.cancel()
                stateTask = nil
                actor = nil
                playbackTask = nil
                state = .idle
            } catch {
                guard generation == runGeneration else { return }
                stateTask?.cancel()
                stateTask = nil
                actor = nil
                playbackTask = nil
                state = .failed(EffectErrorPresenter.message(for: error, language: languageProvider()))
            }
        }
        return state
    }

    func pause() {
        guard state == .running, let actor else { return }
        state = .paused
        Task { await actor.pause() }
    }

    func resume() {
        guard state == .paused, let actor else { return }
        let resumeLifecycle = isLifecyclePaused
        isLifecyclePaused = false
        Task {
            if resumeLifecycle { await actor.resumeAfterForeground() }
            await actor.resume()
        }
    }

    func stop() {
        generation &+= 1
        let activeActor = actor
        actor = nil
        playbackTask?.cancel()
        playbackTask = nil
        stateTask?.cancel()
        stateTask = nil
        isLifecyclePaused = false
        if let activeActor { Task { await activeActor.stop() } }
        state = .idle
    }

    func connectionLost() {
        guard let actor else { return }
        state = .preparing
        Task { await actor.connectionLost() }
    }

    func suspendForBackground() {
        guard let actor else { return }
        isLifecyclePaused = true
        state = .paused
        Task { await actor.lifecycleChanged(.background) }
    }

    private func consume(_ actorState: PlaybackState) {
        switch actorState {
        case .idle:
            break
        case .preparing:
            state = .preparing
        case .running:
            state = isLifecyclePaused ? .paused : .running
        case .paused:
            state = .paused
        case .reconnecting:
            state = .preparing
        case .stopping:
            state = .stopping
        case let .failed(message):
            state = .failed(message)
        }
    }
}

enum PlaybackCompositionError: Error, LocalizedError, Sendable {
    case noSelectedProgram

    var errorDescription: String? {
        switch self {
        case .noSelectedProgram: "playback.unavailable.connection-and-effect"
        }
    }
}

@MainActor
@Observable
final class FakePlaybackControlService: PlaybackControlService {
    var state: PlaybackPresentationState
    init(state: PlaybackPresentationState = .idle) { self.state = state }
    @discardableResult func start() -> PlaybackPresentationState { state = .running; return state }
    func pause() { if state == .running { state = .paused } }
    func resume() { if state == .paused { state = .running } }
    func stop() { state = .idle }
    func connectionLost() { state = .failed("playback.disconnected") }
    func suspendForBackground() { if state == .running || state == .preparing { state = .paused } }
}
