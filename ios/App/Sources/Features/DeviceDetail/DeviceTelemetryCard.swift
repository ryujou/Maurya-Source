import MauryaDevice
import SwiftUI

struct DeviceTelemetryCard: View {
    let global: DeviceGlobalState
    let diagnostics: DeviceDiagnostics
    let isEnabled: Bool
    let refresh: @MainActor () async -> Void
    let clear: @MainActor () async -> Void
    @State private var confirmsClear = false
    @State private var isRefreshing = false
    @State private var isClearing = false

    var body: some View {
        MauryaElevatedCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text("DEVICE")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Color.secondary)
                Text("device.information.title")
                    .font(.title2.bold())
                    .foregroundStyle(DesignTokens.Color.onSurface)

                Text(temperature)
                    .font(.title.bold())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("device.temperature")

                HStack {
                    metric(value: voltage, label: "VOLTAGE")
                    metric(value: diagnostics.receiveCount.formatted(), label: "RX")
                    metric(value: global.deviceAddress.formatted(), label: "ADDR")
                }

                Text(
                    String(
                        format: String(localized: "device.address.save.format"),
                        global.deviceAddress.formatted(),
                        global.saveState.formatted()
                    )
                )
                .frame(maxWidth: .infinity)
                .foregroundStyle(DesignTokens.Color.onSurfaceVariant)

                LabeledContent(
                    "device.receive.count",
                    value: "\(diagnostics.receiveCount) / \(diagnostics.receiveOverflowCount)"
                )
                LabeledContent(
                    "device.transmit.drop",
                    value: "\(diagnostics.transmitDropCount) / \(diagnostics.parseErrorCount)"
                )

                HStack(spacing: DesignTokens.Spacing.standard) {
                    Button("device.refresh", systemImage: "arrow.clockwise", action: refreshAction)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        .disabled(isEnabled == false || isRefreshing || isClearing)
                    Button("device.diagnostics.clear", systemImage: "trash", role: .destructive) {
                        confirmsClear = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                    .disabled(isEnabled == false || isRefreshing || isClearing)
                    .confirmationDialog(
                        "device.diagnostics.clear.confirm.title",
                        isPresented: $confirmsClear,
                        titleVisibility: .visible
                    ) {
                        Button("device.diagnostics.clear.confirm", role: .destructive, action: clearAction)
                    } message: {
                        Text("device.diagnostics.clear.confirm.message")
                    }
                }
            }
        }
        .accessibilityIdentifier("device-telemetry-card")
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(DesignTokens.Color.onSurface)
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    private var temperature: String {
        String(format: "%.2f °C", Double(diagnostics.temperatureCelsiusTimes100) / 100)
    }

    private var voltage: String {
        String(format: "%.3f V", Double(diagnostics.vddaMillivolts) / 1_000)
    }

    private func refreshAction() {
        isRefreshing = true
        Task {
            await refresh()
            isRefreshing = false
        }
    }

    private func clearAction() {
        isClearing = true
        Task {
            await clear()
            isClearing = false
        }
    }
}
