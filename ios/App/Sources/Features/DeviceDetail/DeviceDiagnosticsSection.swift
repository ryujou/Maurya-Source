import MauryaDevice
import SwiftUI

struct DeviceDiagnosticsSection: View {
    let diagnostics: DeviceDiagnostics
    let temperature: String
    let clear: @MainActor () async -> Void
    @State private var confirmsClear = false
    @State private var isClearing = false

    var body: some View {
        Section("device.diagnostics") {
            LabeledContent("device.temperature", value: temperature)
            LabeledContent("device.vdda", value: "\(diagnostics.vddaMillivolts) mV")
            LabeledContent("device.receive.count", value: diagnostics.receiveCount.formatted())
            LabeledContent("device.receive.overflow", value: diagnostics.receiveOverflowCount.formatted())
            LabeledContent("device.transmit.drop", value: diagnostics.transmitDropCount.formatted())
            LabeledContent("device.errors", value: diagnostics.parseErrorCount.formatted())
            Button("device.diagnostics.clear", systemImage: "trash", role: .destructive) {
                confirmsClear = true
            }
            .disabled(isClearing)
            .frame(minHeight: 44)
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

    private func clearAction() {
        isClearing = true
        Task {
            await clear()
            isClearing = false
        }
    }
}
