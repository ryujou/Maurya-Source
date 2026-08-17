import Foundation
import MauryaAnalysis
import MauryaEffects
import MauryaResources

@MainActor
struct AppDependencies {
    let deviceDiscovery: any DeviceDiscoveryService
    let deviceControl: any DeviceControlService
    let shareImport: any ShareImportService
    let resources: any ResourceLibraryService
    let effects: any EffectProgramService
    let analysis: any AnalysisControlService
    let playback: any PlaybackControlService
    let ota: any OTAAvailabilityService
    let language: AppLanguageSettings
    let runtime: AppRuntimeState
    let isUITestFixture: Bool
    let editorRecoveryFixturePrepared: Bool

    static func live() -> AppDependencies {
        let language = AppLanguageSettings()
        let deviceService = LiveDeviceService()
        let analysisHub = AnalysisInputHub()
        let analysisService = LiveAnalysisControlService(hub: analysisHub)
        let effectsDirectory = URL.applicationSupportDirectory.appending(path: "Maurya/Effects", directoryHint: .isDirectory)
        let palettesDirectory = URL.applicationSupportDirectory.appending(path: "Maurya/Palettes", directoryHint: .isDirectory)
        let paletteRepository = CustomPaletteRepository(
            storage: FileCustomPaletteStorage(rootURL: palettesDirectory)
        )
        let effectService: any EffectProgramService
        var effectRepository: EffectProgramRepository?
        do {
            let repository = try EffectProgramRepository(
                storage: FileEffectProgramStorage(directoryURL: effectsDirectory)
            )
            effectRepository = repository
            effectService = try LiveEffectProgramService(
                repository: repository,
                language: { language.effectPresentationLanguage }
            )
        } catch {
            effectRepository = nil
            effectService = UnavailableEffectProgramService(
                error: error,
                language: language.effectPresentationLanguage
            )
        }
        let playbackService = LivePlaybackControlService(
            programProvider: { try effectService.compileSelected() },
            contextProvider: { deviceService.playbackContext() },
            inputSourceProvider: { AnalysisPlaybackInputSource(hub: analysisHub) },
            languageProvider: { language.effectPresentationLanguage }
        )
        let shareService: any ShareImportService
        if let effectRepository {
            do {
                shareService = try LiveShareImportService.production(
                    effectRepository: effectRepository,
                    paletteRepository: paletteRepository
                )
            } catch {
                shareService = UnavailableShareImportService()
            }
        } else {
            shareService = UnavailableShareImportService()
        }
        return AppDependencies(
            deviceDiscovery: deviceService,
            deviceControl: deviceService,
            shareImport: shareService,
            resources: LiveResourceLibraryService(repository: paletteRepository),
            effects: effectService,
            analysis: analysisService,
            playback: playbackService,
            ota: LiveOTAAvailabilityService(contextProvider: { deviceService.OTAContext() }),
            language: language,
            runtime: AppRuntimeState(),
            isUITestFixture: false,
            editorRecoveryFixturePrepared: false
        )
    }

    static func placeholder() -> AppDependencies {
        let unavailableEffects = UnavailableEffectProgramService(error: PlaybackCompositionError.noSelectedProgram)
        return AppDependencies(
            deviceDiscovery: UnavailableDeviceDiscoveryService(),
            deviceControl: UnavailableDeviceControlService(),
            shareImport: UnavailableShareImportService(),
            resources: FakeResourceLibraryService(),
            effects: unavailableEffects,
            analysis: FakeAnalysisControlService(),
            playback: FakePlaybackControlService(),
            ota: LiveOTAAvailabilityService(environment: [:]),
            language: AppLanguageSettings(),
            runtime: AppRuntimeState(),
            isUITestFixture: false,
            editorRecoveryFixturePrepared: false
        )
    }

    /// Deterministic, offline composition used only when the UI test runner
    /// supplies its private launch argument. It deliberately exposes unavailable
    /// hardware and production-service gates instead of simulating success.
    static func uiTesting(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        let languageStore = FileAppLanguageStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "MauryaUITests", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString)
                .appendingPathExtension("json")
        )
        let effects = UITestEffectProgramService()
        let share = UITestShareImportService(arguments: arguments)
        let resources = UITestResourceLibraryService()
        let recovered = UITestFixturePreparation.prepareEditorRecovery()
        return AppDependencies(
            deviceDiscovery: UnavailableDeviceDiscoveryService(),
            deviceControl: UnavailableDeviceControlService(),
            shareImport: share,
            resources: resources,
            effects: effects,
            analysis: FakeAnalysisControlService(),
            playback: FakePlaybackControlService(),
            ota: LiveOTAAvailabilityService(environment: [:]),
            language: AppLanguageSettings(store: languageStore),
            runtime: AppRuntimeState(),
            isUITestFixture: true,
            editorRecoveryFixturePrepared: recovered
        )
    }
}
