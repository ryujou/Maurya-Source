import SwiftUI

@main
struct MauryaApp: App {
    @State private var router: AppRouter
    private let dependencies: AppDependencies

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        _router = State(initialValue: AppRouter(path: Self.uiTestPath(arguments)))
        dependencies =
            arguments.contains("-maurya-ui-testing")
            ? AppDependencies.uiTesting(arguments: arguments)
            : AppDependencies.live()
    }

    private static func uiTestPath(_ arguments: [String]) -> [AppRoute] {
        guard arguments.contains("-maurya-ui-testing") else { return [] }
        if arguments.contains("-maurya-ui-route-resources") { return [.resources] }
        if arguments.contains("-maurya-ui-route-effects") { return [.effects] }
        if arguments.contains("-maurya-ui-route-editor") { return [.editor] }
        if arguments.contains("-maurya-ui-route-share") { return [.shareImport(token: nil)] }
        if arguments.contains("-maurya-ui-route-ota") { return [.ota] }
        if arguments.contains("-maurya-ui-route-legal") { return [.legalPrivacy] }
        return []
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                router: router,
                dependencies: dependencies
            )
        }
    }
}
