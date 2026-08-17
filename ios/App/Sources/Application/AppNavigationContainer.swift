import SwiftUI

struct AppNavigationContainer: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var router: AppRouter
    let dependencies: AppDependencies
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                AppSidebarView(router: router)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            } detail: {
                AppDestinationStack(router: router, dependencies: dependencies)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            AppDestinationStack(router: router, dependencies: dependencies)
        }
    }
}
