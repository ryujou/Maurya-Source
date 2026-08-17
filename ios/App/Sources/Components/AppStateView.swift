import SwiftUI

struct AppStateView: View {
    let state: AppContentState

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("state.loading")
            case .empty:
                ContentUnavailableView(
                    "state.empty.title",
                    systemImage: "tray",
                    description: Text("state.empty.message")
                )
            case .error(let message):
                ContentUnavailableView(
                    "state.error.title",
                    systemImage: "exclamationmark.triangle",
                    description: Text(LocalizedStringKey(message))
                )
            case .permissionRequired:
                ContentUnavailableView(
                    "state.permission.title",
                    systemImage: "lock.shield",
                    description: Text("state.permission.message")
                )
            case .disconnected:
                ContentUnavailableView(
                    "state.disconnected.title",
                    systemImage: "cable.connector.slash",
                    description: Text("state.disconnected.message")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.standard)
    }
}
