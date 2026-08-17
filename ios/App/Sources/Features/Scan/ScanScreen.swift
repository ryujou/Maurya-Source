import MauryaBluetooth
import SwiftUI

struct ScanScreen: View {
    let router: AppRouter
    let discoveryService: any DeviceDiscoveryService

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                controlsCard
                devicesCard
            }
            .padding(DesignTokens.Spacing.standard)
        }
        .background(DesignTokens.Color.background)
        .navigationTitle("scan.title")
        .accessibilityIdentifier("scan-screen")
        .onAppear { discoveryService.returnToDeviceList() }
        .onDisappear { discoveryService.stopScanning() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("app.name")
                .font(.title.bold())
                .foregroundStyle(DesignTokens.Color.onSurface)
            Text("app.subtitle")
                .font(.body)
                .foregroundStyle(DesignTokens.Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var controlsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("scan.refresh", systemImage: DesignTokens.Icon.scan) {
                    discoveryService.startScanning()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                .accessibilityIdentifier("scan-start")

                Button("scan.stop", systemImage: "stop.fill") {
                    discoveryService.stopScanning()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                .disabled(discoveryService.scanState != .scanning)
                .accessibilityIdentifier("scan-stop")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mauryaCard()
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("scan.nearby")
                .font(.headline)
                .foregroundStyle(DesignTokens.Color.onSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().overlay(DesignTokens.Color.outline)

            if discoveryService.devices.isEmpty {
                emptyContent
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            } else {
                ForEach(Array(discoveryService.devices.enumerated()), id: \.element.id) { index, device in
                    Button {
                        discoveryService.connect(to: device.id)
                        router.showDevice(id: device.id.uuidString)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: DesignTokens.Icon.device)
                                .font(.title3)
                                .foregroundStyle(DesignTokens.Color.primary)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(DesignTokens.Color.onSurface)
                                    .lineLimit(1)
                                Text(String(format: String(localized: "scan.rssi.format"), device.rssi))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scan-device")
                    .accessibilityHint("scan.connect.hint")
                    if index != discoveryService.devices.indices.last {
                        Divider().overlay(DesignTokens.Color.outline).padding(.leading, 60)
                    }
                }
            }
        }
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Color.outline.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch discoveryService.scanState {
        case .waitingForBluetooth(.unauthorized):
            AppStateView(state: .permissionRequired)
        case .failed(let message):
            AppStateView(state: .error(message: message))
        case .scanning, .connecting:
            HStack(spacing: 10) {
                ProgressView()
                Text("scan.searching")
                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
            }
        default:
            AppStateView(state: .empty)
        }
    }

    private var statusColor: Color {
        switch discoveryService.scanState {
        case .ready: DesignTokens.Color.success
        case .failed, .waitingForBluetooth(.unauthorized), .waitingForBluetooth(.unsupported): DesignTokens.Color.failure
        case .scanning, .connecting: DesignTokens.Color.primary
        default: DesignTokens.Color.onSurfaceVariant
        }
    }

    private var statusText: String {
        switch discoveryService.scanState {
        case .idle: String(localized: "scan.status.idle")
        case .waitingForBluetooth(let state):
            String(localized: String.LocalizationValue("scan.status.bluetooth.\(state.rawValue)"))
        case .scanning: String(localized: "scan.status.scanning")
        case .connecting: String(localized: "scan.status.connecting")
        case .ready: String(localized: "scan.status.ready")
        case .failed: String(localized: "scan.status.failed")
        }
    }
}

private extension View {
    func mauryaCard() -> some View {
        padding(DesignTokens.Spacing.standard)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .stroke(DesignTokens.Color.outline.opacity(0.45), lineWidth: 1)
            )
    }
}
