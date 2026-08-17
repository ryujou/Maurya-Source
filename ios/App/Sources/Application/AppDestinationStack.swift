import SwiftUI

struct AppDestinationStack: View {
    @Bindable var router: AppRouter
    let dependencies: AppDependencies

    var body: some View {
        NavigationStack(path: $router.path) {
            AppHomeView(
                router: router,
                discoveryService: dependencies.deviceDiscovery,
                language: dependencies.language
            )
            .navigationDestination(for: AppRoute.self, destination: destination)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .deviceDetail(let id):
            DeviceDetailView(
                deviceID: id,
                router: router,
                controlService: dependencies.deviceControl,
                resourceService: dependencies.resources,
                effectService: dependencies.effects
            )
        case .shareImport(let token):
            ShareImportView(initialToken: token, importService: dependencies.shareImport)
        case .resources:
            ResourceLibraryView(service: dependencies.resources)
        case .effects:
            EffectLibraryView(router: router, service: dependencies.effects)
        case .editor:
            EffectEditorHostView(
                service: dependencies.effects,
                playbackService: dependencies.playback,
                runtime: dependencies.runtime,
                fixtureRecoveryVisible: dependencies.editorRecoveryFixturePrepared
            )
        case .analysis:
            AnalysisControlView(service: dependencies.analysis, runtime: dependencies.runtime)
        case .playback:
            PlaybackControlView(service: dependencies.playback, runtime: dependencies.runtime)
        case .ota:
            OTAWorkflowView(service: dependencies.ota)
        case .reviewerGuide:
            HardwareReviewGuideView()
        case .legalPrivacy:
            LegalPrivacyView()
        }
    }
}
