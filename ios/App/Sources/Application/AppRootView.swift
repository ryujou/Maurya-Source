import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Bindable var router: AppRouter
    let dependencies: AppDependencies

    var body: some View {
        AppNavigationContainer(router: router, dependencies: dependencies)
            .tint(DesignTokens.Color.accent)
            .preferredColorScheme(.dark)
            .environment(\.locale, dependencies.language.locale)
            .environment(\.dynamicTypeSize, effectiveDynamicTypeSize)
            .environment(\.mauryaDifferentiateWithoutColor, effectiveDifferentiateWithoutColor)
            .environment(\.layoutDirection, effectiveLayoutDirection)
            .safeAreaInset(edge: .bottom) {
                if dependencies.isUITestFixture {
                    Label("ui.fixture.banner", systemImage: "testtube.2")
                        .font(.caption)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        .background(.bar)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("ui-test-fixture-banner")
                        .accessibilityValue(fixtureEnvironmentValue)
                } else if dependencies.runtime.allowsRealtimeExecution == false {
                    Label(
                        LocalizedStringKey(dependencies.runtime.messageKey),
                        systemImage: dependencies.runtime.constraint == .thermal ? "thermometer.high" : "battery.25percent"
                    )
                    .font(.callout)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                    .background(.bar)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .onOpenURL { url in
                AppLog.lifecycle.notice("Received a deep link; validating without logging its value")
                _ = router.handle(url: url)
            }
            .onChange(of: scenePhase) {
                guard scenePhase != .active else { return }
                AppLog.lifecycle.notice("Scene left active; stopping analysis and pausing playback")
                dependencies.analysis.stop()
                dependencies.playback.suspendForBackground()
            }
            .onChange(of: dependencies.runtime.constraint) {
                guard dependencies.runtime.allowsRealtimeExecution == false else { return }
                dependencies.analysis.stop()
                dependencies.playback.suspendForBackground()
            }
            .task {
                dependencies.runtime.refresh()
                for await _ in NotificationCenter.default.notifications(
                    named: .NSProcessInfoPowerStateDidChange
                ) {
                    dependencies.runtime.refresh()
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(
                    named: ProcessInfo.thermalStateDidChangeNotification
                ) {
                    dependencies.runtime.refresh()
                }
            }
    }

    private var fixtureEnvironmentValue: String {
        "\(colorScheme == .dark ? "dark" : "light");accessibility=\(effectiveDynamicTypeSize.isAccessibilitySize);differentiate=\(effectiveDifferentiateWithoutColor);reduceMotion=\(effectiveReduceMotion);rtl=\(effectiveLayoutDirection == .rightToLeft)"
    }

    private var fixtureArguments: [String] {
        dependencies.isUITestFixture ? ProcessInfo.processInfo.arguments : []
    }

    private var effectiveDynamicTypeSize: DynamicTypeSize {
        fixtureArguments.contains("-maurya-ui-accessibility-xxxl") ? .accessibility5 : dynamicTypeSize
    }

    private var effectiveDifferentiateWithoutColor: Bool {
        fixtureArguments.contains("-maurya-ui-differentiate-without-color") || differentiateWithoutColor
    }

    private var effectiveReduceMotion: Bool {
        fixtureArguments.contains("-maurya-ui-reduce-motion") || reduceMotion
    }

    private var effectiveLayoutDirection: LayoutDirection {
        fixtureArguments.contains("-maurya-ui-rtl") ? .rightToLeft : layoutDirection
    }

}
