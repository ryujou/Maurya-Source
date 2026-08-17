import SwiftUI

struct PlaybackStatusText: View {
    let state: PlaybackPresentationState

    var body: some View {
        switch state {
        case .idle: Text("playback.state.idle")
        case .preparing: Text("playback.state.preparing")
        case .running: Text("playback.state.running")
        case .paused: Text("playback.state.paused")
        case .stopping: Text("playback.state.stopping")
        case .unavailable(let reason): Text(LocalizedStringKey(reason))
        case .failed(let message): Text(LocalizedStringKey(message))
        }
    }
}
