import MauryaAnalysis
import MauryaEffects
import SwiftUI

struct AnalysisControlView: View {
    let service: any AnalysisControlService
    let runtime: AppRuntimeState

    var body: some View {
        Form {
            Section("analysis.permission.context") {
                Text("analysis.permission.message")
                Text("analysis.foreground.only").foregroundStyle(.secondary)
                if runtime.allowsRealtimeExecution == false {
                    Label(LocalizedStringKey(runtime.messageKey), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("analysis.controls") {
                Toggle(
                    "analysis.virtual.enabled",
                    isOn: Binding(
                        get: { service.virtualInputsEnabled },
                        set: { service.setVirtualInputsEnabled($0) }
                    )
                )
                Button("analysis.start.motion", systemImage: "gyroscope") { service.start(.motion) }
                    .disabled(service.virtualInputsEnabled || runtime.allowsRealtimeExecution == false)
                Button("analysis.start.audio", systemImage: "waveform") { service.start(.audio) }
                    .disabled(service.virtualInputsEnabled || runtime.allowsRealtimeExecution == false)
                Button("analysis.stop", systemImage: "stop.fill", action: service.stop)
                    .disabled(isActive == false)
            }
            if service.virtualInputsEnabled {
                Section("analysis.virtual.inputs") {
                    virtualSlider("analysis.input.motion", key: .sensorMotion, range: 0...1, fallback: 0)
                    virtualSlider("analysis.input.roll", key: .sensorRoll, range: -180...180, fallback: 0)
                    virtualSlider("analysis.input.light", key: .sensorLight, range: 0...2_000, fallback: 0)
                    virtualSlider("analysis.input.level", key: .audioLevel, range: 0...1, fallback: 0)
                    virtualSlider("analysis.input.bpm", key: .audioBPM, range: 40...240, fallback: 120)
                }
            } else {
                Section("analysis.calibration") {
                    Button("analysis.zero.attitude", systemImage: "scope", action: service.zeroAttitude)
                    VStack(alignment: .leading) {
                        LabeledContent("analysis.audio.sensitivity") {
                            Text(service.audioSensitivity.formatted(.number.precision(.fractionLength(2))))
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { service.audioSensitivity },
                                set: { service.setAudioSensitivity($0) }
                            ),
                            in: 0.25...4
                        )
                    }
                }
            }
            Section("analysis.status") {
                LabeledContent("analysis.state") {
                    AnalysisStatusText(state: service.state)
                }
            }
            if let snapshot = service.snapshot {
                Section("analysis.snapshot") {
                    if snapshot.requiredInputs.isEmpty {
                        Text("analysis.snapshot.empty").foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.requiredInputs.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { key in
                            LabeledContent(inputName(key)) {
                                if let sample = snapshot.samples[key] {
                                    HStack {
                                        if snapshot.isStale(key) {
                                            Image(systemName: "clock.badge.exclamationmark")
                                                .foregroundStyle(.orange)
                                                .accessibilityLabel("analysis.snapshot.stale")
                                        }
                                        Text(value(sample.value)).monospacedDigit()
                                    }
                                } else {
                                    Text("analysis.snapshot.waiting").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("feature.analysis")
        .onDisappear(perform: service.stop)
    }

    private var isActive: Bool {
        switch service.state {
        case .starting, .running: true
        default: false
        }
    }

    private func inputName(_ key: RuntimeInputKey) -> String {
        key.rawValue.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    private func value(_ value: EffectValue) -> String {
        switch value {
        case let .number(number): number.formatted(.number.precision(.fractionLength(3)))
        case let .boolean(boolean): String(localized: boolean ? "value.yes" : "value.no")
        case let .colour(colour): "H\(colour.hue) S\(colour.saturation) V\(colour.value)"
        case let .target(target): target.rawValue
        case let .list(_, values): "\(values.count)"
        }
    }

    @ViewBuilder
    private func virtualSlider(
        _ title: LocalizedStringKey,
        key: RuntimeInputKey,
        range: ClosedRange<Double>,
        fallback: Double
    ) -> some View {
        let current: Double =
            if case let .number(value) = service.snapshot?.samples[key]?.value {
                value
            } else {
                fallback
            }
        VStack(alignment: .leading) {
            LabeledContent(title) {
                Text(current.formatted(.number.precision(.fractionLength(2))))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { current },
                    set: { service.setVirtualInput(key, value: $0) }
                ),
                in: range
            )
        }
    }

}
