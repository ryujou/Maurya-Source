import MauryaDevice
import SwiftUI

struct DeviceIndividualGroupsCard: View {
    let groups: [DeviceGroupState]
    let isEnabled: Bool
    let apply: @MainActor (Int, DeviceGroupState) async -> Void
    @State private var isExpanded = false

    var body: some View {
        MauryaElevatedCard {
            VStack(spacing: DesignTokens.Spacing.standard) {
                Button(action: toggleExpanded) {
                    HStack {
                        Text(isExpanded ? "device.advanced.groups.close" : "device.advanced.groups.open")
                            .bold()
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("advanced-groups-toggle")
                .accessibilityValue(isExpanded ? "expanded" : "collapsed")

                if isExpanded {
                    LazyVStack(spacing: DesignTokens.Spacing.standard) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                            DeviceGroupControl(
                                index: index,
                                state: group,
                                isEnabled: isEnabled,
                                apply: { updated in await apply(index, updated) }
                            )
                            .id("\(index)-\(group.mode.rawValue)-\(group.hue)-\(group.saturation)-\(group.value)-\(group.parameter)")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("individual-groups-card")
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}
