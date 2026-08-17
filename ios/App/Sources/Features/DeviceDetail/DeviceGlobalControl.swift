import MauryaDevice
import SwiftUI

struct DeviceGlobalControl: View {
    let isEnabled: Bool
    let applyScene: @MainActor (DeviceGlobalState) async -> Void
    let applyGlobalLED: @MainActor (DeviceGlobalState) async -> Void

    private let baseState: DeviceGlobalState
    @State private var sceneMode: SceneMode
    @State private var sceneParameter: Double
    @State private var brightness: Double
    @State private var redGain: Double
    @State private var greenGain: Double
    @State private var blueGain: Double
    @State private var isApplyingScene = false
    @State private var isApplyingLED = false

    init(
        state: DeviceGlobalState,
        isEnabled: Bool,
        applyScene: @escaping @MainActor (DeviceGlobalState) async -> Void,
        applyGlobalLED: @escaping @MainActor (DeviceGlobalState) async -> Void
    ) {
        self.isEnabled = isEnabled
        self.applyScene = applyScene
        self.applyGlobalLED = applyGlobalLED
        baseState = state
        _sceneMode = State(initialValue: state.sceneMode)
        _sceneParameter = State(initialValue: Double(state.sceneParameter))
        _brightness = State(initialValue: Double(state.brightness))
        _redGain = State(initialValue: Double(state.redGain))
        _greenGain = State(initialValue: Double(state.greenGain))
        _blueGain = State(initialValue: Double(state.blueGain))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.standard) {
            MauryaElevatedCard {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.standard) {
                    Text("SCENE")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Color.secondary)
                    Text("device.scene.title")
                        .font(.title2.bold())
                        .foregroundStyle(DesignTokens.Color.onSurface)
                    LazyVGrid(columns: modeColumns, spacing: DesignTokens.Spacing.compact) {
                        ForEach(SceneMode.allCases, id: \.rawValue) { mode in
                            MauryaModeButton(
                                title: sceneName(mode),
                                isSelected: sceneMode == mode,
                                isEnabled: isEnabled && isApplyingScene == false,
                                action: { sceneMode = mode }
                            )
                            .accessibilityIdentifier("scene-mode-\(mode.rawValue)")
                        }
                    }
                    LabeledContent("device.scene.mode", value: sceneName(sceneMode))
                        .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                    valueSlider("device.scene.parameter", value: $sceneParameter)
                    Button("device.scene.apply", systemImage: "sparkles", action: applySceneAction)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        .disabled(isEnabled == false || isApplyingScene)
                        .accessibilityIdentifier("apply-scene")
                }
            }
            .accessibilityIdentifier("scene-card")

            MauryaElevatedCard {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.standard) {
                    Text("MASTER")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Color.secondary)
                    Text("device.global.lighting.title")
                        .font(.title2.bold())
                        .foregroundStyle(DesignTokens.Color.onSurface)
                    valueSlider("device.brightness", value: $brightness)
                    valueSlider("device.red.gain", value: $redGain)
                    valueSlider("device.green.gain", value: $greenGain)
                    valueSlider("device.blue.gain", value: $blueGain)
                    Button("device.global.apply", systemImage: "lightbulb.max", action: applyLEDAction)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                        .disabled(isEnabled == false || isApplyingLED)
                        .accessibilityIdentifier("apply-global")
                }
            }
            .accessibilityIdentifier("global-light-card")
        }
    }

    private func valueSlider(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: Int(value.wrappedValue).formatted())
            Slider(value: value, in: 0...255, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(Int(value.wrappedValue).formatted())
        }
    }

    private func applySceneAction() {
        isApplyingScene = true
        Task {
            await applyScene(currentState)
            isApplyingScene = false
        }
    }

    private func applyLEDAction() {
        isApplyingLED = true
        Task {
            await applyGlobalLED(currentState)
            isApplyingLED = false
        }
    }

    private func sceneName(_ mode: SceneMode) -> String {
        let key = "device.scene.mode.\(mode.rawValue)"
        return String(localized: String.LocalizationValue(key))
    }

    private var modeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.compact), count: 2)
    }

    private var currentState: DeviceGlobalState {
        DeviceGlobalState(
            sceneMode: sceneMode,
            sceneParameter: UInt16(sceneParameter.rounded()),
            brightness: UInt16(brightness.rounded()),
            redGain: UInt16(redGain.rounded()),
            greenGain: UInt16(greenGain.rounded()),
            blueGain: UInt16(blueGain.rounded()),
            saveState: baseState.saveState,
            deviceAddress: baseState.deviceAddress
        )
    }
}
