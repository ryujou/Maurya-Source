import SwiftUI

enum DeviceSection: String, CaseIterable, Identifiable, Sendable {
    case console
    case characters
    case help
    case effects

    var id: Self { self }

    var title: LocalizedStringKey {
        LocalizedStringKey(titleKey)
    }

    var titleKey: String {
        switch self {
        case .console: "device.section.console"
        case .characters: "device.section.characters"
        case .help: "device.section.help"
        case .effects: "device.section.effects"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .console: "device.pending.console"
        case .characters: "device.pending.characters"
        case .help: "device.pending.help"
        case .effects: "device.pending.effects"
        }
    }
}
