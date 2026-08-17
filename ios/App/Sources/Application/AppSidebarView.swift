import SwiftUI

struct AppSidebarView: View {
    @Bindable var router: AppRouter

    var body: some View {
        List {
            Section {
                Button("scan.title", systemImage: "dot.radiowaves.left.and.right", action: router.showRoot)
                    .accessibilityIdentifier("sidebar-devices")
                    .accessibilityAddTraits(isDeviceSectionSelected ? .isSelected : [])
            }

            Section("app.features") {
                routeButton("feature.effects", systemImage: "wand.and.stars", route: .effects, id: "effects")
                routeButton("feature.analysis", systemImage: "waveform.path.ecg", route: .analysis, id: "analysis")
                routeButton(
                    "share.title",
                    systemImage: "square.and.arrow.up",
                    route: .shareImport(token: nil),
                    id: "share"
                )
                routeButton("feature.ota", systemImage: "arrow.triangle.2.circlepath", route: .ota, id: "ota")
            }
        }
        .navigationTitle("Maurya")
        .accessibilityIdentifier("sidebar-navigation")
    }

    private func routeButton(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        route: AppRoute,
        id: String
    ) -> some View {
        Button {
            router.select(route)
        } label: {
            Label(titleKey, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-\(id)")
        .accessibilityAddTraits(isSelected(route) ? .isSelected : [])
    }

    private var isDeviceSectionSelected: Bool {
        guard let first = router.path.first else { return true }
        if case .deviceDetail = first { return true }
        return false
    }

    private func isSelected(_ route: AppRoute) -> Bool {
        guard let first = router.path.first else { return false }
        switch (first, route) {
        case (.effects, .effects), (.analysis, .analysis), (.shareImport, .shareImport), (.ota, .ota):
            return true
        default:
            return false
        }
    }
}
