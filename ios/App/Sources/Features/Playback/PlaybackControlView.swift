import SwiftUI

struct PlaybackControlView: View {
    let service: any PlaybackControlService
    let runtime: AppRuntimeState

    var body: some View {
        Form {
            Section("playback.foreground") {
                Text("playback.foreground.message")
                LabeledContent("playback.state") {
                    PlaybackStatusText(state: service.state)
                }
                if runtime.allowsRealtimeExecution == false {
                    Label(LocalizedStringKey(runtime.messageKey), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("playback.controls") {
                Button("playback.start", systemImage: "play.fill") { service.start() }
                    .disabled(canStart == false)
                Button("playback.pause", systemImage: "pause.fill", action: service.pause)
                    .disabled(service.state != .running)
                Button("playback.resume", systemImage: "playpause.fill", action: service.resume)
                    .disabled(service.state != .paused)
                Button("playback.stop", systemImage: "stop.fill", action: service.stop)
                    .disabled(canStop == false)
            }
            Section("playback.gate") {
                Label("playback.device.gate", systemImage: "iphone.and.arrow.forward")
                Label("playback.background.gate", systemImage: "moon.zzz")
            }
        }
        .navigationTitle("feature.playback")
    }

    private var canStart: Bool {
        runtime.allowsRealtimeExecution && (service.state == .idle || isTerminal)
    }

    private var canStop: Bool {
        switch service.state {
        case .preparing, .running, .paused, .stopping: true
        default: false
        }
    }

    private var isTerminal: Bool {
        switch service.state {
        case .unavailable, .failed: true
        default: false
        }
    }
}
