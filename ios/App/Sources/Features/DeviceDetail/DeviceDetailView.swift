import MauryaBluetooth
import SwiftUI

struct DeviceDetailView: View {
    let deviceID: String
    let router: AppRouter
    let controlService: any DeviceControlService
    let resourceService: any ResourceLibraryService
    let effectService: any EffectProgramService
    @SceneStorage("device-detail-section") private var selectedSection = DeviceSection.console

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.standard) {
            DeviceDetailHeaderCard(
                connectionStatus: connectionDescription,
                saveState: controlService.snapshot?.global.saveState,
                isReady: isReady,
                back: router.showRoot,
                reconnect: controlService.reconnect,
                disconnect: controlService.disconnect,
                share: { router.showShareImport() }
            )
            .padding(.horizontal, DesignTokens.Spacing.standard)

            DeviceSectionSelector(selection: $selectedSection)
                .padding(.horizontal, DesignTokens.Spacing.standard)

            content
        }
        .padding(.top, DesignTokens.Spacing.compact)
        .background(DesignTokens.Color.background)
        .navigationTitle("device.title")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isReady) {
            guard isReady else { return }
            await controlService.refresh()
            await controlService.runTelemetryPolling()
        }
        .accessibilityIdentifier("device-detail-\(deviceID)")
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .console:
            console
        case .characters:
            SupportColorBrowserView(
                service: resourceService,
                controlService: controlService
            )
        case .help:
            DeviceHelpView()
        case .effects:
            EffectLibraryView(router: router, service: effectService)
        }
    }

    @ViewBuilder
    private var console: some View {
        if isReady == false {
            VStack(spacing: DesignTokens.Spacing.standard) {
                ProgressView()
                Text(connectionDescription)
                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                Button("device.reconnect", action: controlService.reconnect)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: DesignTokens.Size.minimumHitTarget)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot = controlService.snapshot {
            DeviceConsoleView(snapshot: snapshot, controlService: controlService)
        } else {
            AppStateView(state: controlService.isRefreshing ? .loading : .empty)
        }
    }

    private var isReady: Bool {
        if case .ready = controlService.connectionState { return true }
        return false
    }

    private var connectionDescription: String {
        let key: String
        switch controlService.connectionState {
        case .idle:
            key = "scan.status.idle"
        case .waitingForBluetooth:
            key = "state.permission.message"
        case .scanning:
            key = "scan.status.scanning"
        case .connecting, .discoveringServices, .discoveringCharacteristics, .subscribing,
            .reconnectBackoff, .disconnecting:
            key = "scan.status.connecting"
        case .ready:
            key = "scan.status.ready"
        case .failed:
            key = "state.disconnected.message"
        }
        return String(localized: String.LocalizationValue(key))
    }
}
