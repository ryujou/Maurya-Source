import SwiftUI

struct DeviceDetailHeaderCard: View {
    let connectionStatus: String
    let saveState: UInt16?
    let isReady: Bool
    let back: () -> Void
    let reconnect: () -> Void
    let disconnect: () -> Void
    let share: () -> Void

    var body: some View {
        MauryaElevatedCard {
            VStack(spacing: DesignTokens.Spacing.standard) {
                HStack(spacing: DesignTokens.Spacing.standard) {
                    Text("M")
                        .font(.title.bold())
                        .foregroundStyle(DesignTokens.Color.onPrimary)
                        .frame(width: DesignTokens.Size.minimumHitTarget, height: DesignTokens.Size.minimumHitTarget)
                        .background(DesignTokens.Color.primary)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("app.name")
                            .font(.title2.bold())
                        Text("device.detail.subtitle")
                            .foregroundStyle(DesignTokens.Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: DesignTokens.Spacing.compact) {
                    statusBadge(connectionStatus, highlighted: isReady)
                    statusBadge(saveStateText, highlighted: saveState != 0)
                }

                HStack(spacing: DesignTokens.Spacing.compact) {
                    Button("navigation.back", action: back)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        .accessibilityIdentifier("device-back")
                    Button("device.reconnect", action: reconnect)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                    Button("device.disconnect", role: .destructive, action: disconnect)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        .disabled(isReady == false)
                        .accessibilityIdentifier("device-disconnect")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("share.open", systemImage: "square.and.arrow.up", action: share)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
            }
        }
        .accessibilityIdentifier("device-header-card")
    }

    private func statusBadge(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.callout)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(highlighted ? DesignTokens.Color.primaryContainer : DesignTokens.Color.surfaceHigh)
            .clipShape(Capsule())
    }

    private var saveStateText: String {
        guard let saveState else { return String(localized: "device.save.state") }
        return "\(String(localized: "device.save.state")): \(saveState)"
    }
}
