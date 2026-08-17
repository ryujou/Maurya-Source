import MauryaDevice
import SwiftUI

struct DeviceGroupControl: View {
    let index: Int?
    let isEnabled: Bool
    let apply: @MainActor (DeviceGroupState) async -> Void

    @State private var mode: GroupMode
    @State private var hue: Double
    @State private var saturation: Double
    @State private var value: Double
    @State private var parameter: Double
    @State private var isApplying = false

    init(
        index: Int?,
        state: DeviceGroupState,
        isEnabled: Bool,
        apply: @escaping @MainActor (DeviceGroupState) async -> Void
    ) {
        self.index = index
        self.isEnabled = isEnabled
        self.apply = apply
        _mode = State(initialValue: state.mode)
        _hue = State(initialValue: Double(state.hue))
        _saturation = State(initialValue: Double(state.saturation))
        _value = State(initialValue: Double(state.value))
        _parameter = State(initialValue: Double(state.parameter))
    }

    var body: some View {
        MauryaElevatedCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.standard) {
                Text(eyebrow)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Color.secondary)

                HStack {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(DesignTokens.Color.onSurface)
                    Spacer()
                    Circle()
                        .fill(previewColor)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(DesignTokens.Color.onSurface, lineWidth: 1))
                        .accessibilityLabel("device.color.preview")
                }

                LazyVGrid(columns: modeColumns, spacing: DesignTokens.Spacing.compact) {
                    modeButton(.steady)
                    modeButton(.strobe)
                }
                LabeledContent("device.mode", value: modeName(mode))
                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)

                valueSlider("device.hue", value: $hue, range: 0...359)
                valueSlider("device.saturation", value: $saturation, range: 0...255)
                valueSlider("device.value", value: $value, range: 0...255)
                if mode == .strobe {
                    valueSlider("device.parameter", value: $parameter, range: 0...255)
                    Text(
                        String(
                            format: String(localized: "device.strobe.period.format"),
                            DeviceGroupDraft.strobePeriodMilliseconds(speed: Int(parameter.rounded()))
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                }

                Button(LocalizedStringKey(index == nil ? "device.apply.all" : "device.apply"), action: applyAction)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                    .disabled(isEnabled == false || isApplying)
                    .accessibilityIdentifier(index == nil ? "all-groups-apply" : "group-\((index ?? 0) + 1)-apply")
            }
        }
        .accessibilityIdentifier(index == nil ? "all-groups-card" : "group-card-\((index ?? 0) + 1)")
    }

    private func valueSlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: Int(value.wrappedValue).formatted())
            Slider(value: value, in: range, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(Int(value.wrappedValue).formatted())
        }
    }

    private func modeName(_ mode: GroupMode) -> String {
        let key = "device.mode.\(mode.rawValue)"
        return String(localized: String.LocalizationValue(key))
    }

    private func modeButton(_ candidate: GroupMode) -> some View {
        MauryaModeButton(
            title: modeName(candidate),
            isSelected: quickMode == candidate,
            isEnabled: isEnabled && isApplying == false,
            action: { mode = candidate }
        )
        .accessibilityIdentifier(
            index == nil
                ? "all-groups-mode-\(candidate.rawValue)"
                : "group-\((index ?? 0) + 1)-mode-\(candidate.rawValue)"
        )
    }

    private var modeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.compact), count: 2)
    }

    private var quickMode: GroupMode {
        mode == .strobe ? .strobe : .steady
    }

    private var previewColor: Color {
        Color(hue: hue / 360, saturation: saturation / 255, brightness: value / 255)
    }

    private func applyAction() {
        isApplying = true
        Task {
            await apply(
                DeviceGroupState(
                    mode: mode,
                    hue: UInt16(hue.rounded()),
                    saturation: UInt16(saturation.rounded()),
                    value: UInt16(value.rounded()),
                    parameter: UInt16(parameter.rounded())
                )
            )
            isApplying = false
        }
    }

    private var eyebrow: String {
        guard let index else { return "7 CHANNELS" }
        return "GROUP \(index + 1)"
    }

    private var title: String {
        guard let index else { return String(localized: "device.groups.all") }
        return String(format: String(localized: "device.group.format"), index + 1)
    }
}

struct DeviceGroupDraft: Equatable, Sendable {
    var mode: GroupMode
    var hue: UInt16
    var saturation: UInt16
    var value: UInt16
    var parameter: UInt16

    init(_ state: DeviceGroupState) {
        mode = state.mode
        hue = state.hue
        saturation = state.saturation
        value = state.value
        parameter = state.parameter
    }

    var state: DeviceGroupState {
        DeviceGroupState(
            mode: mode,
            hue: hue,
            saturation: saturation,
            value: value,
            parameter: parameter
        )
    }

    static func strobePeriodMilliseconds(speed: Int) -> Int {
        30 + ((255 - min(max(speed, 0), 255)) * 220) / 255
    }
}
