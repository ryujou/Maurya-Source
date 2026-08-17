import SwiftUI

struct AppHomeView: View {
    let router: AppRouter
    let discoveryService: any DeviceDiscoveryService
    let language: AppLanguageSettings

    var body: some View {
        ScanScreen(router: router, discoveryService: discoveryService)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("app.features", systemImage: "square.grid.2x2") {
                        Button("feature.effects", systemImage: "wand.and.stars") { router.show(.effects) }
                        Button("feature.analysis", systemImage: "waveform.path.ecg") { router.show(.analysis) }
                        Button("feature.ota", systemImage: "arrow.triangle.2.circlepath") { router.show(.ota) }
                    }
                    .accessibilityIdentifier("features-menu")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("language.title", systemImage: "globe") {
                        ForEach(AppLanguageChoice.allCases) { choice in
                            Button {
                                language.select(choice)
                            } label: {
                                if language.selection == choice {
                                    Label(LocalizedStringKey(choice.titleKey), systemImage: "checkmark")
                                } else {
                                    Text(LocalizedStringKey(choice.titleKey))
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("language-menu")
                }
            }
    }
}
