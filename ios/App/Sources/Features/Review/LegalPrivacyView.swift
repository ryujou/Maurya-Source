import SwiftUI

struct LegalPrivacyView: View {
    var body: some View {
        List {
            Section("legal.privacy.title") {
                Text("legal.privacy.local")
                Text("legal.privacy.external.gate")
                    .foregroundStyle(.secondary)
            }
            Section("legal.data.title") {
                Label("legal.data.audio", systemImage: "waveform")
                Label("legal.data.motion", systemImage: "gyroscope")
                Label("legal.data.share", systemImage: "square.and.arrow.up")
            }
            Section("legal.ota.title") {
                Text("legal.ota.risk")
                Text("legal.ota.gate")
                    .foregroundStyle(.secondary)
            }
            Section("legal.materials.title") {
                Text("legal.materials.review")
            }
            Section("legal.third.party.title") {
                Text(notices)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("legal.title")
        .accessibilityIdentifier("legal-privacy")
    }

    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
            let value = try? String(contentsOf: url, encoding: .utf8)
        else {
            return String(localized: "legal.third.party.unavailable")
        }
        return value
    }
}
