import MauryaDevice
import SwiftUI

struct DeviceConsoleView: View {
    let snapshot: DeviceSnapshot
    let controlService: any DeviceControlService

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.standard) {
                operationStatus

                DeviceTelemetryCard(
                    global: snapshot.global,
                    diagnostics: snapshot.diagnostics,
                    isEnabled: controlsEnabled,
                    refresh: { await controlService.refresh() },
                    clear: { await controlService.clearDiagnostics() }
                )

                DeviceGlobalControl(
                    state: snapshot.global,
                    isEnabled: controlsEnabled,
                    applyScene: { state in await controlService.applyScene(state) },
                    applyGlobalLED: { state in await controlService.applyGlobalLED(state) }
                )
                .id(globalIdentity)

                if let first = snapshot.groups.first {
                    DeviceGroupControl(
                        index: nil,
                        state: first,
                        isEnabled: controlsEnabled,
                        apply: { state in await controlService.applyAllGroups(state) }
                    )
                    .id("all-\(first.mode.rawValue)-\(first.hue)-\(first.saturation)-\(first.value)-\(first.parameter)")
                }

                DeviceIndividualGroupsCard(
                    groups: snapshot.groups,
                    isEnabled: controlsEnabled,
                    apply: { index, state in
                        await controlService.applyGroup(index: index, state: state)
                    }
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.standard)
            .padding(.bottom, DesignTokens.Spacing.standard)
        }
        .background(DesignTokens.Color.background)
        .accessibilityIdentifier("device-console")
    }

    @ViewBuilder
    private var operationStatus: some View {
        if let messageKey = controlService.operationMessageKey {
            Label(LocalizedStringKey(messageKey), systemImage: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.Color.success)
                .mauryaStatusSurface()
                .accessibilityIdentifier("device-operation-success")
        }

        if let error = controlService.operationError {
            Label(operationErrorText(error), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Color.failure)
                .mauryaStatusSurface()
                .accessibilityIdentifier("device-operation-error")
        }

        if ProcessInfo.processInfo.arguments.contains("-maurya-physical-write-validation") {
            MauryaElevatedCard {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    Text("device.validation.title")
                        .font(.headline)
                    Text("device.validation.description")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                    Button("device.validation.run", systemImage: "checkmark.shield.fill") {
                        Task { await controlService.runReversibleWriteValidation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                    .disabled(controlsEnabled == false)
                    .accessibilityIdentifier("device-write-validation-run")
                }
            }
        }
    }

    private var controlsEnabled: Bool {
        if case .ready = controlService.connectionState {
            return controlService.isPerformingAction == false
        }
        return false
    }

    private var globalIdentity: String {
        let global = snapshot.global
        return [
            global.sceneMode.rawValue,
            global.sceneParameter,
            global.brightness,
            global.redGain,
            global.greenGain,
            global.blueGain,
        ]
        .map(String.init)
        .joined(separator: "-")
    }

    private func operationErrorText(_ error: String) -> String {
        if error == "integration.device.not-ready" {
            return String(localized: "integration.device.pending")
        }
        if error == "device.error.readback.mismatch" {
            return String(localized: "device.error.readback.mismatch")
        }
        return error
    }
}

private extension View {
    func mauryaStatusSurface() -> some View {
        padding(.horizontal, DesignTokens.Spacing.standard)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget, alignment: .leading)
            .background(DesignTokens.Color.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
    }
}
