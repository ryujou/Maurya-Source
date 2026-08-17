import Foundation
import MauryaEffects
import MauryaPlayback
import Testing

@testable import Maurya

@MainActor
struct EffectCompositionTests {
    @Test func programServiceLoadsSavesCopiesAndExportsThroughRepositoryBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "maurya-app-effects-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = try EffectProgramRepository(
            storage: FileEffectProgramStorage(directoryURL: directory),
            defaults: [
                EffectProgram(
                    id: "script-fixture",
                    nameZh: "脚本",
                    nameJa: "スクリプト",
                    createdAt: 1,
                    updatedAt: 1,
                    sourceKind: .script,
                    scriptSource: ##"effect "Fixture" { all.color("#FF0000"); wait(50ms); }"##
                ),
                EffectProgram(
                    id: "second-fixture",
                    nameZh: "脚本二",
                    nameJa: "スクリプト二",
                    createdAt: 2,
                    updatedAt: 2,
                    sourceKind: .script,
                    scriptSource: ##"effect "Fixture 2" { all.color("#0000FF"); wait(50ms); }"##
                ),
            ],
            clock: { 42_000 },
            makeID: { "copy-id" }
        )
        let service = try LiveEffectProgramService(repository: repository, now: { 43_000 })

        await service.load()
        #expect(service.records.count == 2)
        let selected = try #require(service.records.first { $0.program.sourceKind == .script })
        service.select(id: selected.program.id)

        let source = ##"effect "Saved" { all.color("#123456"); wait(25ms); }"##
        let compiled = try await service.save(document: source)
        #expect(compiled.estimatedDurationMilliseconds == 25)

        await service.renameSelected(nameZh: "改名", nameJa: "名前変更")
        #expect(service.selectedRecord()?.program.nameZh == "改名")

        await service.copySelected()
        #expect(service.records.count == 3)
        #expect(service.selectedID == "copy-id")
        let exported = try await service.exportSelected()
        #expect(exported.starts(with: Data("{".utf8)))
        let bundle = try await service.exportAll()
        #expect(String(decoding: bundle, as: UTF8.self).contains("\"programs\""))
    }

    @Test func blocksCanBeCopiedAsEditableMauryaScript() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "maurya-app-block-copy-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = try EffectProgramRepository(
            storage: FileEffectProgramStorage(directoryURL: directory),
            defaults: [],
            clock: { 50_000 }
        )
        let service = try LiveEffectProgramService(repository: repository, now: { 51_000 })

        await service.load()
        await service.create(kind: .blocks, nameZh: "积木", nameJa: "ブロック")
        #expect(service.records.count == 1)
        await service.copySelectedAsScript()

        let copied = try #require(service.selectedRecord()?.program)
        #expect(copied.sourceKind == .script)
        #expect(copied.scriptSource.contains("effect"))
        _ = try service.compileSelected()
    }

    @Test func playbackCompositionFailsClosedWithoutProgramOrConnectedDevice() throws {
        let noProgram = LivePlaybackControlService(
            programProvider: { throw PlaybackCompositionError.noSelectedProgram },
            contextProvider: { nil }
        )
        let noProgramState = noProgram.start()
        #expect(noProgramState == noProgram.state)
        guard case .failed = noProgram.state else {
            Issue.record("Missing program must fail before any transport starts")
            return
        }

        let compiled = try EffectScriptCompiler.compile(
            ##"effect "Ready" { all.color("#123456"); wait(25ms); }"##
        )
        let noDevice = LivePlaybackControlService(
            programProvider: { compiled },
            contextProvider: { nil }
        )
        let noDeviceState = noDevice.start()
        #expect(noDeviceState == .unavailable("playback.unavailable.connection-and-effect"))
        #expect(noDevice.state == .unavailable("playback.unavailable.connection-and-effect"))
    }

    @Test func playbackDoesNotReportRunningBeforeActorIsRunning() async throws {
        let compiled = try EffectScriptCompiler.compile(
            ##"effect "Ready" { all.color("#123456"); wait(25ms); }"##
        )
        let runner = FakePlaybackRunner(state: .preparing)
        let context = DevicePlaybackContext(
            transport: FakeEffectPlaybackTransport(),
            initialGroups: Array(repeating: MauryaEffects.EffectGroupState(), count: 7),
            unitID: 1
        )
        let service = LivePlaybackControlService(
            programProvider: { compiled },
            contextProvider: { context },
            actorFactory: { _, _ in runner }
        )

        service.start()
        await Task.yield()
        await Task.yield()

        #expect(service.state == .preparing)
        service.stop()
        #expect(service.state == .idle)
    }

    @Test func backgroundPausesWithoutDestroyingPlaybackAndResumeRebuildsSession() async throws {
        let compiled = try EffectScriptCompiler.compile(
            ##"effect "Ready" { all.color("#123456"); wait(25ms); }"##
        )
        let runner = FakePlaybackRunner(state: .running)
        let context = DevicePlaybackContext(
            transport: FakeEffectPlaybackTransport(),
            initialGroups: Array(repeating: MauryaEffects.EffectGroupState(), count: 7),
            unitID: 1
        )
        let service = LivePlaybackControlService(
            programProvider: { compiled },
            contextProvider: { context },
            actorFactory: { _, _ in runner }
        )

        service.start()
        await Task.yield()
        service.suspendForBackground()
        try await Task.sleep(for: .milliseconds(10))
        #expect(service.state == .paused)
        #expect(await runner.backgroundCount() == 1)

        service.resume()
        try await Task.sleep(for: .milliseconds(10))
        #expect(await runner.foregroundResumeCount() == 1)
        #expect(await runner.stopCount() == 0)
        service.stop()
    }
}

private actor FakePlaybackRunner: EffectPlaybackRunning {
    private var value: PlaybackState
    private var backgrounds = 0
    private var foregroundResumes = 0
    private var stops = 0

    init(state: PlaybackState) { value = state }
    func state() -> PlaybackState { value }
    func run(compiled: CompiledEffect, initialGroups: [MauryaEffects.EffectGroupState], unitID: UInt8) async throws {
        try await Task.sleep(for: .seconds(60))
    }
    func pause() { value = .paused }
    func resume() { value = .running }
    func stop() { value = .idle; stops += 1 }
    func connectionLost() { value = .reconnecting }
    func lifecycleChanged(_ lifecycle: PlaybackLifecycle) {
        if lifecycle == .background { backgrounds += 1; value = .paused }
    }
    func resumeAfterForeground() { foregroundResumes += 1; value = .reconnecting }
    func backgroundCount() -> Int { backgrounds }
    func foregroundResumeCount() -> Int { foregroundResumes }
    func stopCount() -> Int { stops }
}

private struct FakeEffectPlaybackTransport: EffectPlaybackTransport {
    func refreshDeviceContext() throws -> PlaybackDeviceContext {
        PlaybackDeviceContext(capabilities: 0x20, geometry: .legacyFirmwareFallback)
    }
    func exchange(_ request: Data) async throws -> Data { Data() }
    func sendBestEffort(_ request: Data) async {}
}
