import MauryaEditor
import SwiftUI

struct EditorStatusView: View {
    let phase: MauryaEditorModel.Phase
    let version: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Label(status, systemImage: icon)
                Spacer()
                if let version { Text(version).font(.footnote.monospaced()).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading) {
                Label(status, systemImage: icon)
                if let version { Text(version).font(.footnote.monospaced()).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var status: LocalizedStringKey {
        switch phase {
        case .idle: "editor.phase.idle"
        case .loading: "editor.phase.loading"
        case .ready: "editor.phase.ready"
        case .failed: "editor.phase.failed"
        case .terminated: "editor.phase.terminated"
        }
    }

    private var icon: String {
        phase == .ready ? "checkmark.circle" : "circle.dotted"
    }
}
