import SwiftUI

struct DeviceHelpView: View {
    private let chapters: [(title: LocalizedStringKey, body: LocalizedStringKey, icon: String)] = [
        ("help.quick.title", "help.quick.body", "play.circle"),
        ("help.buttons.title", "help.buttons.body", "button.programmable"),
        ("help.lighting.title", "help.lighting.body", "lightbulb.max"),
        ("help.palette.title", "help.palette.body", "paintpalette"),
        ("help.blocks.title", "help.blocks.body", "square.grid.3x3"),
        ("help.script.title", "help.script.body", "chevron.left.forwardslash.chevron.right"),
        ("help.algorithms.title", "help.algorithms.body", "function"),
        ("help.sensors.title", "help.sensors.body", "sensor"),
        ("help.network.title", "help.network.body", "network"),
        ("help.recovery.title", "help.recovery.body", "cross.case"),
    ]

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.shareImport(token: nil)) {
                    Label {
                        Text("share.open")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .accessibilityIdentifier("device-help-share-entry")
                NavigationLink(value: AppRoute.ota) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("device.help.ota")
                            Text("device.help.ota.message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
            Section {
                Text("help.intro")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                Section {
                    Label {
                        Text(chapter.body)
                    } icon: {
                        Image(systemName: chapter.icon)
                    }
                } header: {
                    Text(chapter.title)
                }
            }
            Section("help.script.example.title") {
                Text(String(localized: "help.script.example"))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("help.script.example.accessibility"))
            }
            Section("help.offline.title") {
                Text("help.offline.body")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
