import SwiftUI

struct AnalysisStatusText: View {
    let state: AnalysisPresentationState

    var body: some View {
        switch state {
        case .idle:
            Text("analysis.state.idle")
        case .starting(let mode):
            HStack {
                Text("analysis.state.starting")
                Text(modeTitle(mode))
            }
        case .running(let mode):
            HStack {
                Text("analysis.state.running")
                Text(modeTitle(mode))
            }
        case .unavailable(let reason):
            Text(LocalizedStringKey(reason))
        case .failed(let message):
            Text(LocalizedStringKey(message))
        }
    }

    private func modeTitle(_ mode: AnalysisMode) -> LocalizedStringResource {
        switch mode {
        case .motion: "analysis.mode.motion"
        case .audio: "analysis.mode.audio"
        case .virtual: "analysis.mode.virtual"
        }
    }
}
