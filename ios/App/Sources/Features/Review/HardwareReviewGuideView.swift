import SwiftUI

struct HardwareReviewGuideView: View {
    var body: some View {
        List {
            Section("review.without.hardware") {
                NavigationLink(value: AppRoute.resources) { Label("review.resources", systemImage: "photo.on.rectangle.angled") }
                NavigationLink(value: AppRoute.editor) { Label("review.editor", systemImage: "slider.horizontal.3") }
                NavigationLink(value: AppRoute.shareImport(token: nil)) { Label("review.share", systemImage: "checkmark.shield") }
                NavigationLink(value: AppRoute.analysis) { Label("review.analysis", systemImage: "waveform.path.ecg") }
            }
            Section("review.hardware.required") {
                Label("review.ble", systemImage: "antenna.radiowaves.left.and.right")
                NavigationLink(value: AppRoute.playback) { Label("review.playback", systemImage: "play.circle") }
                NavigationLink(value: AppRoute.ota) { Label("review.ota", systemImage: "arrow.triangle.2.circlepath") }
            }
            Section("review.truthful.states") {
                Text("review.truthful.message")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("review.guide.title")
    }
}
