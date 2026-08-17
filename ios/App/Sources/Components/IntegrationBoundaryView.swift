import SwiftUI

struct IntegrationBoundaryView: View {
    let title: LocalizedStringKey
    let availability: IntegrationAvailability

    var body: some View {
        switch availability {
        case .available:
            AppStateView(state: .empty)
        case .unavailable(let reasonKey):
            ContentUnavailableView(
                title,
                systemImage: DesignTokens.Icon.unavailable,
                description: Text(LocalizedStringKey(reasonKey))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DesignTokens.Spacing.standard)
        }
    }
}
