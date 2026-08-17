import MauryaOTA
import SwiftUI

struct OTAWorkflowView: View {
    let service: any OTAAvailabilityService
    @State private var operationTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("ota.preflight") {
                switch service.preflight {
                case .checking:
                    ProgressView("ota.preflight.checking")
                case .ready:
                    Label("ota.preflight.ready", systemImage: "checkmark.shield")
                    if service.canStart == false, isRunning == false {
                        Label("ota.preflight.device-required", systemImage: "cable.connector")
                    }
                case .unavailable(let blockers):
                    ForEach(blockers, id: \.self) { blocker in
                        Label(LocalizedStringKey(blocker), systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("ota.workflow") {
                LabeledContent("ota.current.stage", value: stageName(service.workflowSnapshot.stage))
                if let installed = service.workflowSnapshot.installedVersion {
                    LabeledContent("ota.installed.version", value: installed)
                }
                if let target = service.workflowSnapshot.targetVersion {
                    LabeledContent("ota.target.version", value: target)
                }
                if service.workflowSnapshot.totalBytes > 0 {
                    ProgressView(value: service.workflowSnapshot.progress) {
                        Text("ota.transfer.progress")
                    } currentValueLabel: {
                        Text(service.workflowSnapshot.progress, format: .percent.precision(.fractionLength(0)))
                    }
                    Text(
                        String(
                            format: String(localized: "ota.transfer.bytes.format"),
                            service.workflowSnapshot.confirmedBytes.formatted(.byteCount(style: .file)),
                            service.workflowSnapshot.totalBytes.formatted(.byteCount(style: .file))
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                if let error = service.errorMessage {
                    AppStateView(state: .error(message: error))
                }

                if isRunning {
                    Button("ota.cancel", systemImage: "xmark.circle", role: .destructive) {
                        operationTask?.cancel()
                        operationTask = Task { await service.cancel() }
                    }
                } else {
                    Button("ota.start", systemImage: "arrow.triangle.2.circlepath") {
                        operationTask?.cancel()
                        operationTask = Task { await service.start() }
                    }
                    .disabled(service.canStart == false)
                    if service.canStart == false {
                        Text("ota.start.device-disabled").foregroundStyle(.secondary)
                    }
                }
            }

            Section("ota.gates") {
                Text("ota.gate.message").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("feature.ota")
        .accessibilityIdentifier("ota-workflow")
        .toolbar { Button("ota.refresh", systemImage: "arrow.clockwise", action: service.refresh) }
        .onDisappear {
            guard isRunning else { return }
            operationTask?.cancel()
            operationTask = Task { await service.cancel() }
        }
    }

    private var isRunning: Bool {
        ![.idle, .cancelled, .failed, .succeeded, .upToDate].contains(service.workflowSnapshot.stage)
    }

    private func stageName(_ stage: OTAWorkflowStage) -> String {
        String(localized: String.LocalizationValue("ota.runtime.\(stage.rawValue)"))
    }
}
